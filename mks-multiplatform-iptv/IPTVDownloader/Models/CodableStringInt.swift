//
//  CodableStringInt.swift
//  mks-multiplatform-iptv
//
//  Created by Marcos Asensio on 19/2/25.
//


@propertyWrapper
struct CodableStringInt: Codable {
    var wrappedValue: Int

    // Add this initializer to accept Int directly
    init(wrappedValue: Int) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            wrappedValue = intValue
        } else if let stringValue = try? container.decode(String.self), let intValue = Int(stringValue) {
            wrappedValue = intValue
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Value is not an Int or a String convertible to Int")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }
}


