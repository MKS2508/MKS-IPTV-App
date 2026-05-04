//
//  CodableStringInt.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 19/2/25.
//


@propertyWrapper
public struct CodableStringInt: Codable {
    public var wrappedValue: Int

    // Add this initializer to accept Int directly
    public init(wrappedValue: Int) {
        self.wrappedValue = wrappedValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
        } else if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Value is not an Int or a String convertible to Int")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}


