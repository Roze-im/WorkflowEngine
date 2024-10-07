//
//  StateStore.swift
//  
//
//  Created by Benjamin Garrigues on 27/04/2022.
//

import Foundation

public protocol StateStore {
    func saveState<C: Codable>(state: C?, fileName: String?)
    func loadState<C: Codable>(fileName: String?) -> C?
}
