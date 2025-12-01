//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 26/04/2022.
//

import Foundation
@testable import WorkflowEngine


typealias TestFlowEngineType = WorkflowEngine<AnyTestFlow,
                                              WorkflowIndex<AnyTestFlow>,
                                              TestFlowStateStore,
                                              TestFlowEngineDelegate>

final class TestFlowEngineDelegate: WorkflowEngineDelegate {
    typealias AnyWorkflow = AnyTestFlow
    typealias Index = WorkflowIndex<AnyTestFlow>
    typealias Store = TestFlowStateStore
    
    var progressCalls = [WorkflowId: [(Set<String>,WorkflowProgress)]]()
    var onProgressCall: ((WorkflowId, WorkflowProgress, Set<String>) -> Void)?
    
    /// Controls whether the delegate accepts the flow completion.
    /// Set to `false` to trigger a retry instead of disposal.
    var shouldAcceptProgress: ((WorkflowId, WorkflowProgress, Set<String>) -> Bool)?
    
    func workflowEngine(
        _ engine: TestFlowEngineType,
        flow: WorkflowId,
        didRegisterProgress progress: WorkflowProgress,
        tags: Set<String>
    ) -> Bool {
        progressCalls[flow, default: []].append((tags, progress))
        onProgressCall?(flow, progress, tags)
        return shouldAcceptProgress?(flow, progress, tags) ?? true
    }
}

class TestFlowEngine: TestFlowEngineType {
    
    override func configureFlowDependencies(_ anyFlow: AnyTestFlow) {
        super.configureFlowDependencies(anyFlow)
        anyFlow.testFlow.configure(dependencies: .init(dependency: "42"))
    }
    
    deinit {
        logger(self, .trace, "dealloc")
    }
}
