//
//  ClipboardWriter.swift
//  Currency Tracker
//
//  Created by Codex on 4/13/26.
//

import AppKit

@MainActor
protocol ClipboardWriting: AnyObject {
    func write(_ string: String) -> Bool
}

@MainActor
final class ClipboardWriter: ClipboardWriting {
    func write(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }
}
