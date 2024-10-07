//
//  FileDataStore+WorkFlowEngine.swift
//  RozeEngine-Swift
//
//  Created by Thibaud David on 04/05/2022.
//

import Foundation
import FileDataStore

extension FileDataStore: StateStore {
    public func saveState<C: Codable>(state: C?, fileName: String?) {
        saveModel(state, fileName: fileName)
    }
    public func loadState<C: Codable>(fileName: String?) -> C? {
        loadModel(fileName: fileName)
    }
}
