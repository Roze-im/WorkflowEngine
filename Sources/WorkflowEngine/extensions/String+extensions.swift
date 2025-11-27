//
//  String+extensions.swift
//  WorkflowEngine
//
//  Created by Thibaud David on 27/11/2025.
//

import Foundation

extension String {
  func shortenedUUID() -> String {
      let indexOfUnderscore = firstIndex(of: "_") ?? startIndex
      return prefix(upTo: indexOfUnderscore) + "…" + suffix(6)
  }
  // warning: allowDots = false is legacy behavior. Don't change until you've
  // done an extensive impact evaluation,
  // and written the migration code for renaming queues & dbs (eg: event out & in queues)
  public func asAcceptableFileName(allowDots: Bool = false) -> String {
      let passed = self.unicodeScalars.filter {
          (allowDots && ($0 == ".")) || CharacterSet.alphanumerics.contains($0)
      }
      return String(passed)
  }
}
