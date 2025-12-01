//
//  ConfigurableFlow.swift
//
//
//  Created for unit testing retry mechanisms.
//

import Foundation
@testable import WorkflowEngine

/// A flow with a configurable step that can succeed or fail, useful for testing retry mechanisms.
class ConfigurableFlow: TestflowBase {
    
    enum CodingKeys: CodingKey {
        case configurableStep
    }
    
    var configurableStep: ConfigurableStep
    
    override var testSteps: [TestflowStepBase] {
        return [configurableStep]
    }
    
    override init(identifier: WorkflowId = "configurable_flow_\(UUID().uuidString)", tags: Set<String> = [], waitFor: Set<WorkflowId> = []) {
        configurableStep = ConfigurableStep(identifier: "configurable_step")
        super.init(identifier: identifier, tags: tags, waitFor: waitFor)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        configurableStep = try container.decode(ConfigurableStep.self, forKey: .configurableStep)
        try super.init(from: decoder)
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(configurableStep, forKey: .configurableStep)
        try super.encode(to: encoder)
    }
}

