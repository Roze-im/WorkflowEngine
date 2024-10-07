//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 28/04/2022.
//

import Foundation

/// Steps that block until a notification is sent on the notification center, with the step identifier
/// Used in unit-testing.
class BlockingStep: TestflowStepBase {

    enum CodingKeys: CodingKey {
    }
    
    
    let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
    
    required init(identifier: WorkflowStepId) {
        super.init(identifier: identifier)
        registerForNotification()
    }
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
    }
    
    override func prepareAfterUnarchiving() {
        super.prepareAfterUnarchiving()
        registerForNotification()
    }
    
    func registerForNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(unlock),
            name: NSNotification.Name(rawValue: identifier),
            object: nil
        )
    }

    override func execute() {
        super.execute()
        // Waiting here blocks the current queue (processor flow dispatchqueue).
        // However, because we're using a dispatchsemaphore, we know GDC won't try
        // to execute anything on that queue while it's blocked. The notification
        // observer and the "unlock" function will be executed on an available queue.
        // Note that this is a unit-testing flow only.
        // It is NOT meant to be used in the app.
        semaphore.wait()
        updateProgress(to: .success)
    }
    
    @objc func unlock() {
        semaphore.signal()
    }
    
    override func dispose() {
        super.dispose()
        NotificationCenter.default.removeObserver(self)
    }
}

/// Blocking flow contains only one step that blocks until it receives a notification with its identifier
/// The identifier for the step is the one for the flow with "-step" suffix.
/// aka: to unlock flow "myflow", send a notification with name "myflow-step"
class BlockingFlow: TestflowBase {

    var blockingStep : BlockingStep
    override var steps: [WorkflowStep] { return [blockingStep] }
    
    
    override init(identifier: WorkflowId, tags: Set<String> = [], waitFor: Set<WorkflowId> = []) {
        blockingStep = BlockingStep(
            identifier: identifier+"-step"
        )
        super.init(identifier: identifier, tags: tags, waitFor: waitFor)
    }
    
    private enum CodingKeys: String, CodingKey {
        case blockingStep
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        blockingStep = try container.decode(BlockingStep.self, forKey: .blockingStep)
        try super.init(from: decoder)
    }

    override func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(blockingStep, forKey: .blockingStep)
        try super.encode(to: encoder)
    }
}
