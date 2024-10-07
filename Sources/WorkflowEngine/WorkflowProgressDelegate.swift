//
//  WorkflowDelegate.swift
//  
//
//  Created by Benjamin Garrigues on 27/04/2022.
//

import Foundation

public protocol WorkflowProgressDelegate: AnyObject {
    func flow(flowId: WorkflowId,
              didProgress progress: WorkflowProgress,
              tags: Set<String>)
}
