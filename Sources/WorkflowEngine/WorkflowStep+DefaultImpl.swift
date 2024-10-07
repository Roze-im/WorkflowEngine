//
//  WorkflowStep+DefaultImpl.swift
//  
//
//  Created by Benjamin Garrigues on 27/04/2022.
//

import Foundation

extension WorkflowStep {
    public func configure(logger: @escaping Logger, progressDelegate: WorkflowStepProgressDelegate) {
        self.logger = logger
        self.progressDelegate = progressDelegate
    }

    public func updateProgress(to: WorkflowStepProgress, warnDelegate: Bool = true) {
        logger?(self, .trace, "updating progress to \(to)")
        self.progress = to
        if warnDelegate {
            progressDelegate?.stepDidProgress(step: self)
        }
    }
}
