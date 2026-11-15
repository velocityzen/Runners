import FP
import Foundation

/// JSON with ISO 8601 dates, with or without fractional seconds (GitLab sends them).
public enum JSONCoding {
    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) -> Result<T, RunnersError> {
        Result { try decoder.decode(type, from: data) }
            .mapError { .decoding(String(describing: $0)) }
    }

    public static func encode<T: Encodable>(_ value: T) -> Result<String, RunnersError> {
        Result { try encoder.encode(value) }
            .map { String(decoding: $0, as: UTF8.self) }
            .mapError { .encoding(String(describing: $0)) }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(decodeDate)
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    @Sendable
    static func decodeDate(_ decoder: any Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let date = parseDate(raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Not an ISO 8601 date: \(raw)"
            )
        }
        return date
    }

    static func parseDate(_ raw: String) -> Date? {
        (try? Date(raw, strategy: .iso8601))
            ?? (try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
    }
}
