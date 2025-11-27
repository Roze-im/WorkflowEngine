//
//  LogLevel.swift
//  WorkflowEngine
//
//  Created by Thibaud David on 07/10/2024.
//


public typealias WELogger = (_ caller: Any?, LogLevel, String) -> Void

public enum LogLevel {
    case error, warning, debug, trace
}
