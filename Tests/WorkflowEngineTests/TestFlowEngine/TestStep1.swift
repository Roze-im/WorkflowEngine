//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 28/04/2022.
//

import Foundation
@testable import WorkflowEngine

class TestStep1: TestflowStepBase {
    
    var output: String = "0"
    override func execute() {
        updateProgress(to: .inProgress(0.0))
        output = "1"
        updateProgress(to: .success)
    }
}

