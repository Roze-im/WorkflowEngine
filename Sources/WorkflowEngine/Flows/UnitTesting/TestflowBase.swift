//
//  TestflowBase.swift
//  
//
//  Created by Benjamin Garrigues on 28/04/2022.
//

import Foundation


/// TestFlowBase is a sample implementation of a worfklow base class
/// It is used in unit tests for flows in the Workflow package, but is provided in case one need it too for its own unit tests.
/// In can also be used a an example on how to implement a real world flow base class
/// with external dependencies being injected
open class TestflowBase: Workflow {
    
    private enum CodingKeys: CodingKey {
        case identifier
        case tags
        case waitFor
    }
    
    public var identifier: WorkflowId
    
    var testSteps: [TestflowStepBase] { return [] }
    public var steps: [WorkflowStep] { testSteps }
    
    public var tags: Set<String>
    
    public var waitFor: Set<WorkflowId>
    
    public var logger: Logger?
    public weak var progressDelegate: WorkflowProgressDelegate?
    
    var customDependency: String?
    
    public var flowMutexQueue: DispatchQueue = DispatchQueue(label: "baseflow_mutex_dq")

    init(identifier: WorkflowId, tags: Set<String> = [], waitFor: Set<WorkflowId> = []) {
        self.identifier = identifier
        self.tags = tags
        self.waitFor = waitFor
        self.flowMutexQueue = DispatchQueue(label: "\(identifier)_mutex_queue", qos: .utility)
    }

    func configure(dependencies: TestflowStepBase.Dependencies) {
        customDependency = dependencies.dependency
        testSteps.forEach { $0.configure(dependencies: dependencies)}
    }
}
