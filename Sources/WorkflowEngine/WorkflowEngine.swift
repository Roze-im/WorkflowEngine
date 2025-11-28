import Foundation

public protocol WorkflowEngineDelegate: AnyObject {

    associatedtype AnyWorkflow: AnyWorkflowType
    associatedtype Index: WorkflowIndex<AnyWorkflow>
    associatedtype Store: StateStore

    func workflowEngine(
        _ engine: WorkflowEngine<AnyWorkflow, Index, Store, Self>,
        flow: WorkflowId,
        didRegisterProgress: WorkflowProgress,
        tags: Set<String>
    )
}

open class WorkflowEngine<
    AnyWorkflow: AnyWorkflowType,
    Index: WorkflowIndex<AnyWorkflow>,
    Store: StateStore,
    Delegate: WorkflowEngineDelegate
> where
    Delegate.AnyWorkflow == AnyWorkflow,
    Delegate.Index == Index,
    Delegate.Store == Store
{
    var stateStore: StateStore
    var logger: WELogger
    var flowIndex: Index
    let stateSerializationFileName: String
    public weak var delegate: Delegate?

    
    public init(
        stateStore: StateStore,
        logger: @escaping WELogger,
        stateSerializationFileName: String = "WorkflowEngineState",
        resumeFlowsAfterUnarchiving: Bool = true
    ) {
        self.stateStore = stateStore
        self.logger = logger
        self.stateSerializationFileName = stateSerializationFileName
        self.flowIndex = stateStore.loadState(fileName: stateSerializationFileName) ?? .init()
        
        restoreFlowStatesAfterUnarchiving()
        if resumeFlowsAfterUnarchiving {
            self.resumeFlowsAfterUnarchiving()
        }
    }

    public func flows(matching predicate: (AnyWorkflow) -> Bool) -> [AnyWorkflow] {
        assert(Thread.isMainThread, "should be called on main thread")
        return flowIndex.flows.compactMap { predicate($1.anyFlow) ? $1.anyFlow : nil }
    }
    
    private func restoreFlowStatesAfterUnarchiving() {
        logger(self, .debug, "Restore flow states after unarchiving")
        let flowsStillInProgress = Index()
        for entry in flowIndex.flows.values {
            if let progress = restoreFlowAfterUnarchiving(entry.anyFlow) {
                flowsStillInProgress.insertOrUpdate(.init(
                    anyFlow: entry.anyFlow,
                    progress: progress
                ))
            }
        }
        self.flowIndex = flowsStillInProgress
    }
    
    public func restoreFlowAfterUnarchiving(_ anyFlow: AnyWorkflow) -> WorkflowProgress? {
        let flow = anyFlow.flow
        logger(self, .debug, "…restoring \(flow.identifier)")

        //restore flow state (progress, outputs, etc) after unarchiving
        configureFlowDependencies(anyFlow)
        flow.prepareAfterUnarchiving()

        //filter out flows that are successful
        let progress = flow.progress ?? .pending
        switch progress {
        case .failure where flow.shouldRetryOnErrorUponUnarchived():
            logger(
                self,
                .debug,
                "flow \(flow) was archived in error state. retry it."
            )
            flow.reset()
        case .success,
             .failure:
            logger(
                self,
                .debug,
                "flow \(flow) was archived in successful or error state. dispose it."
            )
            flow.dispose()
            return nil
        default:
            break
        }
        return progress
    }

    public func flow(_ flowId: WorkflowId) -> AnyWorkflow? {
        assert(Thread.isMainThread, "processor should be interacted with on the main thread")
        return flowIndex.flows[flowId]?.anyFlow
    }
    
    public func executeNewFlow(_ anyFlow: AnyWorkflow) {
        let flow = anyFlow.flow
        assert(Thread.isMainThread, "processor should be interacted with on the main thread")
        logger(self, .debug, "executeNewFlow: \(anyFlow)")
        configureFlowDependencies(anyFlow)

        if flowIndex.flows[anyFlow.flow.identifier] != nil {
            logger(self, .debug, "flow \(flow.identifier) already exists")
            return
        }
        
        flowIndex.insertOrUpdate(.init(anyFlow: anyFlow, progress: .pending))
        archiveFlows()
        executeFlowOrMarkAsPendingIfWaiting(
            flow: flow,
            executeAsResume: false
        )
    }
    
    private func executeFlowOrMarkAsPendingIfWaiting(
        flow: Workflow,
        executeAsResume: Bool
    ) {
        guard areFlowsCompleted(flowIds: flow.waitFor) else {
            logger(self, .debug, "flow \(flow.identifier.shortenedUUID()) has incomplete dependent flows. Mark as pending")
            flowIndex.markAsPending(flowId: flow.identifier, pending: true)
            return
        }
        if executeAsResume {
            flow.resume()
        } else {
            flow.start()
        }
    }
    
    /// This function returns true if a flow is completed.
    /// *IMPORTANT : an _unknown_ flow is considered _completed_*
    private func areFlowsCompleted(flowIds: Set<WorkflowId>) -> Bool {
        guard !flowIds.isEmpty else { return true }
        for flowId in flowIds {
            if flowIndex.flows[flowId]?.progress.isSuccessful == false {
                return false
            }
        }
        return true
    }
    
    private func startPendingFlows(waitingFor flowId: WorkflowId) {
        // make sure flow doesn't have other dependencies
        for anyFlow in flowIndex.pendingFlows() {
            let flow = anyFlow.flow
            guard flow.waitFor.contains(flowId) else { continue }
            if areFlowsCompleted(flowIds: flow.waitFor) {
                flowIndex.markAsPending(flowId: flow.identifier, pending: false)
                flow.start()
            }
        }
    }

    open func configureFlowDependencies(_ anyFlow: AnyWorkflow) {
        logger(self, .trace, "configure flow dependencies for \(anyFlow.flow.shortIdentifier)")
        // rebinding internal dependencies
        anyFlow.flow.progressDelegate = self
        anyFlow.flow.logger = logger
        anyFlow.flow.steps.forEach {
            $0.logger = logger
            $0.progressDelegate = anyFlow.flow
        }
    }
    
    private func updateFlowProgress(withId flowId: WorkflowId,
                                    progress: WorkflowProgress) {
        logger(self, .debug, "flow \(flowId) did update progress to \(progress)")
        
        guard flowIndex.updateProgress(
            progress,
            forFlowWithId: flowId
        ) != nil else {
            logger(self, .error, "updating progress for unknown flow: \(flowId)")
            return
        }
        
        if progress.isSuccessful {
            startPendingFlows(waitingFor: flowId)
        }
    }
    
    func archiveFlows() {
        logger(self, .debug, "archive all flows")
        stateStore.saveState(state: flowIndex, fileName: stateSerializationFileName)
    }
    
    func disposeFlow(withId flowId: WorkflowId) {
        assert(Thread.isMainThread, "processor should be interacted with on the main thread")
        logger(self, .debug, "dispose flow \(flowId)")
        if let removedFlow = flowIndex.remove(
            flowWithId: flowId
        ) {
            removedFlow.flow.dispose()
            archiveFlows()
        } else {
            logger(self, .warning, "… flow to dispose not found :\(flowId)")
        }
    }
    
    func resumeFlowsAfterUnarchiving() {
        logger(self, .debug, "resumeFlowsAfterUnarchiving")
        flowIndex.flows.forEach { entry in
            executeFlowOrMarkAsPendingIfWaiting(
                flow: entry.value.anyFlow.flow,
                executeAsResume: true
            )
        }
    }
}

extension WorkflowEngine: WorkflowProgressDelegate {
    public func flow(
        flowId: WorkflowId,
        didProgress progress: WorkflowProgress,
        tags: Set<String>
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Note : it may be a good idea to do the update on a background thread
            // because updateFlowProgress serialize on disk.
            self.updateFlowProgress(withId: flowId,
                                    progress: progress)
            self.delegate?.workflowEngine(
                self,
                flow: flowId,
                didRegisterProgress: progress,
                tags: tags
            )
            if case .success = progress {
                self.disposeFlow(withId: flowId)
            }
        }
    }
}
