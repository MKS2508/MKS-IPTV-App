//
//  CastProtobuf.swift
//  mks-multiplatform-iptv
//
//  Manual protobuf encoder/decoder for the Google Cast V2 CastMessage wire format.
//  No external protobuf library — uses raw LEB128 varint and length-delimited encoding.
//

import Foundation
import IPTVCore

// MARK: - CastMessage

/// A decoded Cast V2 protocol message.
///
/// Wire format: `[4-byte big-endian length][protobuf bytes]`
///
/// Protobuf fields:
/// | Field # | Name             | Wire Type | Notes                          |
/// |---------|------------------|-----------|--------------------------------|
/// | 1       | protocol_version | varint    | Always 0 (CASTV2_1_0)          |
/// | 2       | source_id        | string    | e.g. "sender-0"                |
/// | 3       | destination_id   | string    | e.g. "receiver-0" / transportId|
/// | 4       | namespace        | string    | Cast namespace URN              |
/// | 5       | payload_type     | varint    | 0 = STRING, 1 = BINARY         |
/// | 6       | payload_utf8     | string    | JSON payload                    |
struct CastMessage: Sendable {

    /// Source identifier (e.g. "sender-0").
    let sourceId: String

    /// Destination identifier (e.g. "receiver-0" or a transport ID).
    let destinationId: String

    /// Cast namespace URN (e.g. "urn:x-cast:com.google.cast.tp.connection").
    let namespace: String

    /// JSON payload string.
    let payloadUtf8: String

    // MARK: - Encoding

    /// Encode this message as a length-prefixed protobuf frame ready to send over the wire.
    /// Returns `[4-byte big-endian length][protobuf bytes]`.
    func encodeFramed() -> Data {
        var body = Data()

        // Field 1: protocol_version = 0 (varint)
        ProtobufEncoder.appendVarintField(to: &body, fieldNumber: 1, value: 0)

        // Field 2: source_id (string)
        ProtobufEncoder.appendStringField(to: &body, fieldNumber: 2, value: sourceId)

        // Field 3: destination_id (string)
        ProtobufEncoder.appendStringField(to: &body, fieldNumber: 3, value: destinationId)

        // Field 4: namespace (string)
        ProtobufEncoder.appendStringField(to: &body, fieldNumber: 4, value: namespace)

        // Field 5: payload_type = 0 (STRING)
        ProtobufEncoder.appendVarintField(to: &body, fieldNumber: 5, value: 0)

        // Field 6: payload_utf8 (string)
        ProtobufEncoder.appendStringField(to: &body, fieldNumber: 6, value: payloadUtf8)

        // Prepend 4-byte big-endian length
        var frame = Data()
        var length = UInt32(body.count).bigEndian
        frame.append(Data(bytes: &length, count: 4))
        frame.append(body)

        return frame
    }

    // MARK: - Decoding

    /// Decode a CastMessage from raw protobuf bytes (without length prefix).
    /// - Parameter data: Raw protobuf bytes.
    /// - Returns: Decoded CastMessage or nil if parsing fails.
    static func decodeFromProtobuf(_ data: Data) -> CastMessage? {
        let fields = ProtobufDecoder.decodeFields(data)

        var sourceId: String?
        var destinationId: String?
        var namespace: String?
        var payloadUtf8: String?

        for field in fields {
            switch field.fieldNumber {
            case 2:
                if case .lengthDelimited(let bytes) = field.value {
                    sourceId = String(data: bytes, encoding: .utf8)
                }
            case 3:
                if case .lengthDelimited(let bytes) = field.value {
                    destinationId = String(data: bytes, encoding: .utf8)
                }
            case 4:
                if case .lengthDelimited(let bytes) = field.value {
                    namespace = String(data: bytes, encoding: .utf8)
                }
            case 6:
                if case .lengthDelimited(let bytes) = field.value {
                    payloadUtf8 = String(data: bytes, encoding: .utf8)
                }
            default:
                // Skip unknown fields (protocol_version, payload_type, etc.)
                break
            }
        }

        guard let src = sourceId,
              let dst = destinationId,
              let ns = namespace,
              let payload = payloadUtf8 else {
            return nil
        }

        return CastMessage(
            sourceId: src,
            destinationId: dst,
            namespace: ns,
            payloadUtf8: payload
        )
    }
}

// MARK: - ProtobufEncoder

/// Minimal protobuf encoder for CastMessage fields.
/// Supports varint (wire type 0) and length-delimited (wire type 2) fields.
enum ProtobufEncoder {

    /// Encode a varint using LEB128 encoding.
    static func encodeVarint(_ value: UInt64) -> Data {
        var data = Data()
        var v = value
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v > 0 {
                byte |= 0x80
            }
            data.append(byte)
        } while v > 0
        return data
    }

    /// Append a varint field (wire type 0) to data.
    static func appendVarintField(to data: inout Data, fieldNumber: Int, value: UInt64) {
        let tag = UInt64((fieldNumber << 3) | 0) // wire type 0
        data.append(encodeVarint(tag))
        data.append(encodeVarint(value))
    }

    /// Append a length-delimited string field (wire type 2) to data.
    static func appendStringField(to data: inout Data, fieldNumber: Int, value: String) {
        let tag = UInt64((fieldNumber << 3) | 2) // wire type 2
        let utf8 = Data(value.utf8)
        data.append(encodeVarint(tag))
        data.append(encodeVarint(UInt64(utf8.count)))
        data.append(utf8)
    }
}

// MARK: - ProtobufDecoder

/// Minimal protobuf decoder for CastMessage fields.
/// Decodes varint and length-delimited fields, skips unknown wire types gracefully.
enum ProtobufDecoder {

    /// Decoded field value.
    enum FieldValue {
        case varint(UInt64)
        case lengthDelimited(Data)
    }

    /// A decoded protobuf field.
    struct Field {
        let fieldNumber: Int
        let value: FieldValue
    }

    /// Decode all fields from protobuf data.
    static func decodeFields(_ data: Data) -> [Field] {
        var fields: [Field] = []
        var offset = 0

        while offset < data.count {
            // Decode tag varint
            guard let (tag, newOffset) = decodeVarint(data, offset: offset) else { break }
            offset = newOffset

            let wireType = Int(tag & 0x07)
            let fieldNumber = Int(tag >> 3)

            switch wireType {
            case 0: // Varint
                guard let (value, nextOffset) = decodeVarint(data, offset: offset) else { return fields }
                offset = nextOffset
                fields.append(Field(fieldNumber: fieldNumber, value: .varint(value)))

            case 2: // Length-delimited
                guard let (length, nextOffset) = decodeVarint(data, offset: offset) else { return fields }
                offset = nextOffset
                let len = Int(length)
                guard offset + len <= data.count else { return fields }
                let bytes = data.subdata(in: offset..<(offset + len))
                offset += len
                fields.append(Field(fieldNumber: fieldNumber, value: .lengthDelimited(bytes)))

            case 1: // 64-bit fixed — skip 8 bytes
                offset += 8

            case 5: // 32-bit fixed — skip 4 bytes
                offset += 4

            default:
                // Unknown wire type — can't determine size, stop parsing
                return fields
            }
        }

        return fields
    }

    /// Decode a LEB128 varint from data at given offset.
    /// - Returns: Tuple of (decoded value, new offset) or nil if data is insufficient.
    static func decodeVarint(_ data: Data, offset: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var pos = offset

        while pos < data.count {
            let byte = data[pos]
            result |= UInt64(byte & 0x7F) << shift
            pos += 1

            if byte & 0x80 == 0 {
                return (result, pos)
            }

            shift += 7
            if shift >= 64 {
                return nil // Overflow protection
            }
        }

        return nil // Ran out of data
    }
}
