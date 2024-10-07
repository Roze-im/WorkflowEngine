//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 27/04/2022.
//

import Foundation

struct WorkflowAndProgress<AnyWorkflow: AnyWorkflowType>: Codable {
     var anyFlow: AnyWorkflow
     var progress: WorkflowProgress
 }

public class WorkflowIndex<AnyWorkflow: AnyWorkflowType>: Codable {
    var flows: [WorkflowId: WorkflowAndProgress<AnyWorkflow>]
    var pendingFlowIds: Set<WorkflowId>
    public required init() {
        flows = [:]
        pendingFlowIds = []
    }
    
    func pendingFlows() -> [AnyWorkflow] {
        pendingFlowIds.compactMap{ flows[$0]?.anyFlow }
    }
    
    func insertOrUpdate(_ entry: WorkflowAndProgress<AnyWorkflow>) {
        flows[entry.anyFlow.flow.identifier] = entry
    }
    
    /// returns the current progress for the flow
    func updateProgress(_ progress: WorkflowProgress,
                        forFlowWithId flowId: WorkflowId) -> WorkflowProgress? {
        guard let existingFlowAndProgress = flows[flowId] else {
            return nil
        }
        flows[flowId] = .init(
            anyFlow: existingFlowAndProgress.anyFlow,
            progress: progress
        )
        return existingFlowAndProgress.progress
    }
    
    func markAsPending(flowId: WorkflowId, pending: Bool) {
        if pending {
            pendingFlowIds.insert(flowId)
        } else {
            pendingFlowIds.remove(flowId)
        }
    }
    
    /// returns the flow if it was found, nil otherwise
    @discardableResult
    func remove(_ anyFlow: AnyWorkflow) -> AnyWorkflow? {
        return remove(flowWithId: anyFlow.flow.identifier)
    }
    
    /// returns the flow if it was found, nil otherwise
    @discardableResult
    func remove(flowWithId flowId: WorkflowId) -> AnyWorkflow? {
        guard let flow = flows[flowId] else {
            return nil
        }
        flows.removeValue(forKey: flowId)
        pendingFlowIds.remove(flowId)
        return flow.anyFlow
    }
}
