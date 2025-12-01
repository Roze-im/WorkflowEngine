//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 26/04/2022.
//

import Foundation

public typealias WorkflowId = String

public protocol Workflow: Codable, WorkflowStepProgressDelegate {
    var identifier: WorkflowId { get }
    var steps: [WorkflowStep] { get }
    var tags: Set<String> { get }
    var waitFor: Set<WorkflowId> { get }
    var progressDelegate: WorkflowProgressDelegate? { get set }

    var logger: WELogger? { get set }
    var flowMutexQueue: DispatchQueue { get }

    func start()
    func resume()
    func reset()
    func dispose()
    func shouldRetryOnErrorUponUnarchived() -> Bool
}

// Wrapper, usually an enum, that contains all the possible flow types.
public protocol AnyWorkflowType: Codable {
    var flow: Workflow { get }
}
