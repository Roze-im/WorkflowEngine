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
    func workflowEngine(
        _ engine: TestFlowEngineType,
        flow: WorkflowId,
        didRegisterProgress progress: WorkflowProgress,
        tags: Set<String>
    ) {
        progressCalls[flow, default: []].append((tags, progress))
        onProgressCall?(flow, progress, tags)
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
