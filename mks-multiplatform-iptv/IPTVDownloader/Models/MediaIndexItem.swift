//
//  MediaIndexItem.swift
//  mks-multiplatform-iptv
//
//  Protocol to unify Movie and Serie for indexed scrolling
//

import Foundation

// Protocol to unify Movie and Serie for indexed scrolling
protocol MediaIndexItem: Identifiable where ID == Int {
    var name: String { get }
    var addedDate: Date { get }  // Renamed to avoid conflict with existing properties
}

// Extension for Movie to conform to MediaIndexItem
extension Movie: MediaIndexItem {
    var addedDate: Date {
        // Convert timestamp string to Date
        if let timestamp = self.added, 
           let timeInterval = Double(timestamp) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return Date() // Fallback to current date
    }
}

// Extension for Serie to conform to MediaIndexItem
extension Serie: MediaIndexItem {
    var addedDate: Date {
        // Convert lastModified timestamp string to Date
        // lastModified is not optional in Serie
        if let timeInterval = Double(self.lastModified) {
            return Date(timeIntervalSince1970: timeInterval)
        }
        return Date() // Fallback to current date
    }
}