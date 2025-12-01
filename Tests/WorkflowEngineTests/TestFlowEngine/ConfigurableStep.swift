//
//  ConfigurableStep.swift
//
//
//  Created for unit testing retry mechanisms.
//

import Foundation
@testable import WorkflowEngine

/// A step that can be configured to succeed or fail, useful for testing retry mechanisms.
class ConfigurableStep: TestflowStepBase {
    
    /// If true, the step will fail when executed
    var shouldFail: Bool = false
    
    /// Number of times this step has been executed
    var executionCount: Int = 0
    
    /// Called when execution starts, allows test to control behavior
    var onExecute: (() -> Void)?
    
    override func execute() {
        executionCount += 1
        logger?(self, .trace, "\(identifier) executing (attempt #\(executionCount))")
        updateProgress(to: .inProgress(0.0))
        
        onExecute?()
        
        if shouldFail {
            updateProgress(to: .failure("TEST_ERROR", "Configured to fail"))
        } else {
            updateProgress(to: .success)
        }
    }
    
    override func reset() {
        super.reset()
        // Don't reset executionCount - we want to track total executions across retries
    }
}

