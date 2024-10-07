//
//  Workflow+Default.swift
//  
//
//  Created by Benjamin Garrigues on 27/04/2022.
//

import Foundation

extension Workflow {
    
    var shortIdentifier: String {
        return identifier.shortenedUUID()
    }
    
    //automatically deduce flow progress as the one of
    //the last non-pending step
    public var progress: WorkflowProgress? {
        // special case for empty flows
        guard !steps.isEmpty else { return .success }
        
        guard let lastNonPendingIndex = steps.lastIndex(where: { (step) -> Bool in
            if case .pending = step.progress {
                return false
            }
            return true
        }) else {
            //they're all pending
            return .pending
        }
        let lastNonPendingStep = steps[lastNonPendingIndex]
        switch lastNonPendingStep.progress {
        case .failure(let errorCode, let errorMessage):
            return .failure(errorCode: errorCode,
                            errorMessage: errorMessage)
        case .inProgress:
            return .executing(stepAt: lastNonPendingIndex,
                              progress: lastNonPendingStep.progress,
                              totalSteps: steps.count)
        case .success:
            if lastNonPendingIndex == steps.count - 1 {
                return .success
            } else {
                return .executing(stepAt: lastNonPendingIndex,
                                  progress: .success,
                                  totalSteps: steps.count)
            }
        case .cancelled:
            return .cancelled
        case .pending:
            assertionFailure("last non pending state is pending -> error")
            return .pending
        }
    }
    
    func stepInProgress() -> WorkflowStep? {
        return steps.first(where: {
            if case .inProgress = $0.progress {
                return true
            } else {
                return false
            }})
    }


    //Safe update to the flow.
    func performUpdate(_ update:@escaping (Workflow) -> Void ) {
        flowMutexQueue.async {[weak self] in
            guard let self = self else { return }
            update(self)
        }
    }
    
    // MARK: - Default start / pause / resume implementation
    public func start() {
        logger?(self, .trace, "start")
        performUpdate { (flow) in
            flow.executeNextPending()
        }
    }
    
    public func resume() {
        logger?(self, .trace, "resume")

        performUpdate { (flow) in
            if case .failure(let errorCode, let errorMessage) = flow.progress {
                flow.logger?(flow, .debug,
                """
                can't resume flow \(flow.identifier) in failure state with error \(errorCode) : \(errorMessage).
                """)
            } else if let stepInProgress = flow.stepInProgress() {
                //resume the step (if any)
                stepInProgress.execute()
            } else {
                flow.executeNextPending()
            }
        }
    }

    public func executeNextPending() {
        performUpdate { flow in
            if let step = flow.stepInProgress() {
                flow.logger?(flow, .debug,
                """
                trying to execute next pending step while step
                \(step) is still in progress
                """)
                return
            }
            guard let firstPending = flow.steps.first(
                where: {
                    if case .pending = $0.progress { return true }
                    return false
                }
            ) else {
                flow.logger?(flow, .debug,
                    "flow \(flow.shortIdentifier) has no remaining step to execute."
                )
                // special case for totally empty flows.
                // we need to trigger the progress manually.
                if flow.steps.isEmpty {
                    flow.sendProgressToDelegate()
                }
                return
            }
            flow.logger?(flow, .debug,
                "flow \(flow.shortIdentifier) start step \(firstPending.identifier)"
            )
            firstPending.execute()
        }
    }
    
    public func prepareAfterUnarchiving() {
        steps.forEach { $0.prepareAfterUnarchiving() }
    }
    
    public func dispose() {
        logger?(self, .trace, "dispose")
        steps.forEach { $0.dispose() }
    }
    
    public func cancel() {
        steps.forEach { $0.cancel() }
    }
    
    public func sendProgressToDelegate() {
        guard let progress = progress else { return }
        progressDelegate?.flow(
            flowId: self.identifier,
            didProgress: progress,
            tags: tags
        )
    }
    
    public func stepDidProgress(step: WorkflowStep) {
        logger?(self, .trace,
                 """
                 flow \(self.shortIdentifier) step did progress - \(step.identifier) \
                 : \(step.progress), completionValue : \(progress?.completionValue ?? 0)
                 """
        )
        sendProgressToDelegate()
        if case .success = step.progress {
            executeNextPending()
        }
    }
}
