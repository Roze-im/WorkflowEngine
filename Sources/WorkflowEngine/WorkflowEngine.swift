import Foundation

public protocol WorkflowEngineDelegate: AnyObject {

    associatedtype AnyWorkflow: AnyWorkflowType
    associatedtype Index: WorkflowIndex<AnyWorkflow>
    associatedtype Store: StateStore

    /// Called when a flow's progress changes.
    /// - Returns: `true` to proceed with the normal flow lifecycle (dispose on success/failure),
    ///            `false` to retry the flow instead of disposing it.
    func workflowEngine(
        _ engine: WorkflowEngine<AnyWorkflow, Index, Store, Self>,
        flow: WorkflowId,
        didRegisterProgress: WorkflowProgress,
        tags: Set<String>
    ) -> Bool
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
    
    // MARK: - Retry Configuration
    
    /// Base delay for retry (default 1 second)
    public var retryBaseDelay: TimeInterval = 1.0
    
    /// Maximum delay between retries (default 5 minutes)
    public var retryMaxDelay: TimeInterval = 300.0
    
    /// Maximum number of retries (default 10, nil = unlimited)
    public var maxRetryCount: Int? = 10

    
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
                // Reset retry count on app restart - backoff starts fresh
                flowsStillInProgress.insertOrUpdate(.init(
                    anyFlow: entry.anyFlow,
                    progress: progress,
                    retryCount: 0
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
                "flow \(flow) was archived in error state. Will retry with backoff."
            )
            // Reset flow so steps can do their cleanup
            flow.reset()
            // Return .pending since we just reset - will be retried by resumeFlowsAfterUnarchiving
            return .pending

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
            // All flows execute immediately on restart (backoff was reset)
            // If they fail again, backoff will kick in
            executeFlowOrMarkAsPendingIfWaiting(
                flow: entry.value.anyFlow.flow,
                executeAsResume: true
            )
        }
    }
    
    // MARK: - Retry with Exponential Backoff
    
    /// Calculate delay using exponential backoff: baseDelay * 2^retryCount, capped at maxDelay
    private func retryDelay(forRetryCount retryCount: Int) -> TimeInterval {
        let delay = retryBaseDelay * pow(2.0, Double(retryCount))
        return min(delay, retryMaxDelay)
    }
    
    /// Schedule a retry for a flow
    private func scheduleRetry(flowId: WorkflowId) {
        guard let entry = flowIndex.flows[flowId] else { return }
        
        // Check max retries
        if let maxRetries = maxRetryCount, entry.retryCount >= maxRetries {
            logger(self, .warning, "flow \(flowId) exceeded max retries (\(maxRetries)), disposing")
            disposeFlow(withId: flowId)
            return
        }
        
        let flow = entry.anyFlow.flow
        let delay = retryDelay(forRetryCount: entry.retryCount)
        
        // Reset flow immediately so it's archived as pending (survives app restart)
        flow.reset()
        _ = flowIndex.updateProgress(.pending, forFlowWithId: flowId)
        
        // Increment retry count now and persist (so it survives app restart)
        let retryNumber = flowIndex.incrementRetryCount(forFlowWithId: flowId)
        archiveFlows()
        
        logger(self, .debug, "Scheduling retry #\(retryNumber) for flow \(flowId) in \(String(format: "%.1f", delay))s")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.executeRetry(flowId: flowId)
        }
    }
    
    /// Execute a scheduled retry
    private func executeRetry(flowId: WorkflowId) {
        guard let entry = flowIndex.flows[flowId] else {
            logger(self, .debug, "Flow \(flowId) no longer exists, skipping retry")
            return
        }
        
        let flow = entry.anyFlow.flow
        
        logger(self, .debug, "Executing retry #\(entry.retryCount) for flow \(flowId)")
        
        executeFlowOrMarkAsPendingIfWaiting(flow: flow, executeAsResume: false)
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

            self.updateFlowProgress(withId: flowId, progress: progress)
            
            // If delegate returns false on success, retry the flow instead of disposing it
            let shouldAcceptCompletion = self.delegate?.workflowEngine(
                self,
                flow: flowId,
                didRegisterProgress: progress,
                tags: tags
            ) ?? true
            
            switch progress {
            case .success:
                if shouldAcceptCompletion {
                    self.flowIndex.resetRetryCount(forFlowWithId: flowId)
                    self.disposeFlow(withId: flowId)
                } else {
                    // Delegate returned false: retry instead of disposing
                    self.logger(self, .debug, "Delegate rejected flow \(flowId) completion, scheduling retry")
                    self.scheduleRetry(flowId: flowId)
                }
                
            case .failure:
                if self.flowIndex.flows[flowId]?.anyFlow.flow.shouldRetryOnErrorUponUnarchived() == true {
                    self.scheduleRetry(flowId: flowId)
                }
                
            default:
                break
            }
        }
    }
}
