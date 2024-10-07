//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 26/04/2022.
//

import Foundation

public enum WorkflowProgress {
    case pending
    case executing(stepAt: Int,
                   progress: WorkflowStepProgress,
                   totalSteps: Int)
    case success
    case failure(errorCode: WorkflowStepProgress.ErrorCode,
                 errorMessage: String)
    case cancelled

    public var completionValue: Float {
        switch self {
        case .pending:
            return 0
        case .executing(let stepAt, let progress, let totalSteps):
            return (Float(stepAt) + progress.completionValue) / Float(totalSteps)
        case .success:
            return 1
        case .cancelled, .failure:
            return 0
        }
    }
    
    public var isSuccessful: Bool {
        switch self {
        case .success: return true
        default: return false
        }
    }
    
    func isDifferentStepThan(progress: WorkflowProgress) -> Bool {
        switch (self, progress) {
        case (.pending, .pending),
            (.success, .success),
            (.cancelled, .cancelled),
            (.failure, .failure):
            return false
        case (.executing(let stepBefore, _, _), .executing(let stepAfter, _, _)):
            return stepBefore != stepAfter
        default:
            return true
        }
    }

    //computation should be commutative (it should give the same result if we call it on the other flow's progress).
    func syntheticProgress(with otherProgress: WorkflowProgress) -> WorkflowProgress {
        //flows in final states give the other's flow state as a result.
        //Except for failed flows, wich makes the total fail.
        switch (self, otherProgress) {
        //Executing is high priority
        case (.executing(let selfStepAt, let selfProgress, let selfTotalSteps),
              .executing(let otherStepAt, let otherProgress, let otherTotalSteps)):
            return .executing(
                stepAt: selfStepAt + otherStepAt,
                progress: .inProgress(
                    (selfProgress.completionValue + otherProgress.completionValue) / 2
                ), // virtual "in progress" step.
                totalSteps: selfTotalSteps + otherTotalSteps)
        case (.executing, _):
            return self
        case (_, .executing):
            return otherProgress

        case (.success, .pending), (.pending, .success),
             (.cancelled, .pending), (.pending, .cancelled):
            return .pending

        case (.cancelled, .success),
             (.success, .cancelled),
             (.success, .success):
            return .success
        case (.cancelled, .cancelled):
            return .cancelled
        case (.pending, .pending):
            return .pending

        case (.failure, _):
            return self
        case (_, .failure):
            return otherProgress
        }
    }
}

extension WorkflowProgress: Codable {
    enum CodingKeys: String, CodingKey {
        case pending
        case executingStepAt
        case executingProgress
        case executingTotalSteps
        case success
        case failureErrorCode
        case failureErrorMessage
        case cancelled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decode(Bool.self, forKey: .pending)) != nil {
            self = .pending
            return
        }
        if let stepAt = try? container.decode(Int.self, forKey: .executingStepAt),
           let progress = try? container.decode(WorkflowStepProgress.self, forKey: .executingProgress),
           let totalSteps = try? container.decode(Int.self, forKey: .executingTotalSteps) {
            self = .executing(stepAt: stepAt, progress: progress, totalSteps: totalSteps)
            return
        }
        if (try? container.decode(Bool.self, forKey: .success)) != nil {
            self = .success
            return
        }
        if let failureErrorCode = try? container.decode(WorkflowStepProgress.ErrorCode.self,
                                                        forKey: .failureErrorCode),
           let failureErrorMessage = try? container.decode(String.self, forKey: .failureErrorMessage) {
            self = .failure(errorCode: failureErrorCode, errorMessage: failureErrorMessage)
            return
        }
        self = .cancelled
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode(true, forKey: .pending)
        case .executing(let stepAt, let progress, let totalSteps):
            try container.encode(stepAt, forKey: .executingStepAt)
            try container.encode(progress, forKey: .executingProgress)
            try container.encode(totalSteps, forKey: .executingTotalSteps)
        case .success:
            try container.encode(true, forKey: .success)
        case .failure(let errorCode, let errorMessage):
            try container.encode(errorCode, forKey: .failureErrorCode)
            try container.encode(errorMessage, forKey: .failureErrorMessage)
        case .cancelled:
            try container.encode(true, forKey: .cancelled)
        }
    }
}
