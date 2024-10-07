//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 26/04/2022.
//

import Foundation

public typealias WorkflowStepId = String


public protocol WorkflowStepProgressDelegate: AnyObject {
    func stepDidProgress(step: WorkflowStep)
}

public protocol WorkflowStep: AnyObject, Codable {
    
    var identifier: WorkflowStepId { get}
    var progress: WorkflowStepProgress {get set}
    var progressDelegate: WorkflowStepProgressDelegate? {get set}
    var logger: Logger? { get set }
    
    // init(identifier: WorkflowStepId, logSubsystem: LogSubsystem)
    func configure(logger: @escaping Logger, progressDelegate: WorkflowStepProgressDelegate)

    func execute()
    // Called after restoring from disk ,potentially reinjecting dependencies
    func prepareAfterUnarchiving()
    // Called upon flow being cancelled (logout, etc.)
    func cancel()

    func dispose()
}
