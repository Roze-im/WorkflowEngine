//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 29/04/2022.
//

import Foundation

class TestflowStepBase: WorkflowStep {
    struct Dependencies {
        let dependency: String
    }

    enum CodingKeys: CodingKey {
        case identifier
        case progress
    }
    
    var identifier: WorkflowStepId
    
    var progress: WorkflowStepProgress
    
    weak var progressDelegate: WorkflowStepProgressDelegate?
    
    var logger: WELogger?

    var customDependency: String?

    required init(identifier: WorkflowStepId) {
        self.identifier = identifier
        self.progress = .pending
    }
    
    func configure(dependencies: Dependencies) {
        self.customDependency = dependencies.dependency
    }
    
    func execute() {
        logger?(self, .trace, "\(identifier) executing")
        updateProgress(to: .inProgress(0.0))
    }
    
    func prepareAfterUnarchiving() {
        logger?(self, .trace, "\(identifier) prepareAfterUnarchiving")
    }
    
    func cancel() {
        logger?(self, .trace, "\(identifier) cancel")
    }

    func reset() {
        logger?(self, .trace, "\(identifier) reset")
    }

    func dispose() {
        logger?(self, .trace, "\(identifier) dispose")
    }
    
    
}
