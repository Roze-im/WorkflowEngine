//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 29/04/2022.
//

import Foundation
@testable import WorkflowEngine

class TestFlow2: TestflowBase {
    var step1: TestStep1
    var step11: TestStep1
    
    private enum CodingKeys: CodingKey {
        case step1
        case step11
    }
    
    override init(identifier: WorkflowId = "testflow1_\(UUID().uuidString)", tags: Set<String> = [], waitFor: Set<WorkflowId> = []) {
        step1 = .init(identifier: "step1")
        step11 = .init(identifier: "step11")
        super.init(identifier: identifier, tags: tags, waitFor: waitFor)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        step1 = try container.decode(TestStep1.self, forKey: .step1)
        step11 = try container.decode(TestStep1.self, forKey: .step11)
        try super.init(from: decoder)
    }
    
    override var testSteps: [TestflowStepBase] {
        return [step1, step11]
    }
    
    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(step1, forKey: .step1)
        try container.encode(step11, forKey: .step11)
        try super.encode(to: encoder)
    }
}
