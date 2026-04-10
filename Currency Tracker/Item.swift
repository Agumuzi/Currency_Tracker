//
//  Item.swift
//  Currency Tracker
//
//  Created by Thomas Tao on 4/10/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
