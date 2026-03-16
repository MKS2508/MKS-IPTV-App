//
//  Syncable.swift
//  mks-multiplatform-iptv
//
//  Protocol for types that can be synchronized via CloudKit.
//

import Foundation
import CloudKit

/// A type that can be serialized to and from CloudKit records.
///
/// Conforming types must provide a stable identifier and support
/// round-trip conversion between the local model and `CKRecord`.
protocol Syncable: Identifiable, Codable, Sendable where ID == UUID {
    /// The CloudKit record type name for this model.
    static var recordType: String { get }

    /// Converts the model to a CloudKit record.
    /// - Parameter zoneID: The record zone to create the record in.
    /// - Returns: A `CKRecord` populated with the model's fields.
    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord

    /// Creates a model instance from a CloudKit record.
    /// - Parameter record: The `CKRecord` to read from.
    /// - Returns: A populated model, or `nil` if the record is malformed.
    static func fromRecord(_ record: CKRecord) -> Self?

    /// The date this item was last modified locally.
    /// Used for conflict resolution (last-modified-wins strategy).
    var lastModifiedDate: Date { get }
}
