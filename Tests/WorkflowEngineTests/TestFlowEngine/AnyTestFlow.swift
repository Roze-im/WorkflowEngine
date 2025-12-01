//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 28/04/2022.
//

import Foundation
@testable import WorkflowEngine

enum AnyTestFlow: AnyWorkflowType {
    
    var flow: Workflow {
        return testFlow
    }
    
    var testFlow: TestflowBase {
        switch self {
        case .blocking(let flow): return flow
        case .flow1(let flow): return flow
        case .flow2(let flow): return flow
        case .configurable(let flow): return flow
        }
    }

    case blocking(BlockingFlow)
    case flow1(TestFlow1)
    case flow2(TestFlow2)
    case configurable(ConfigurableFlow)
}
