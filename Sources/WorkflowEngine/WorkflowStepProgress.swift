//
//  File.swift
//  
//
//  Created by Benjamin Garrigues on 26/04/2022.
//

import Foundation

public enum WorkflowStepProgress: Equatable, Codable {
    public typealias ErrorCode = String

    case pending
    case inProgress(Float)
    case success
    case failure(ErrorCode, String)
    case cancelled

    var completionValue: Float {
        switch self {
        case .inProgress(let progress):
            return progress
        case .success, .failure:
            return 1.0
        case .cancelled, .pending:
            return 0.0
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case pending
        case inProgressValue
        case success
        case failureErrorCode
        case failureMessage
        case cancelled
    }
    enum DecodingError: Error {
        case decodingError(String)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if (try? container.decode(Bool.self, forKey: .pending)) != nil {
            self = .pending
            return
        }
        if let progress = try? container.decode(Float.self, forKey: .inProgressValue) {
            self = .inProgress(progress)
            return
        }
        if (try? container.decode(Bool.self, forKey: .success)) != nil {
            self = .success
            return
        }
        if (try? container.decode(Bool.self, forKey: .cancelled)) != nil {
            self = .cancelled
            return
        }
        if let errorCode = try? container.decode(WorkflowStepProgress.ErrorCode.self, forKey: .failureErrorCode),
           let errorMessage = try? container.decode(String.self, forKey: .failureMessage) {
            self = .failure(errorCode, errorMessage)
            return
        }
        throw DecodingError.decodingError("no key found")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .pending:
            try container.encode(true, forKey: .pending)
        case .inProgress(let progress):
            try container.encode(progress, forKey: .inProgressValue)
        case .success:
            try container.encode(true, forKey: .success)
        case .cancelled:
            try container.encode(true, forKey: .cancelled)
        case .failure(let code, let message):
            try container.encode(code, forKey: .failureErrorCode)
            try container.encode(message, forKey: .failureMessage)
        }
    }
}
