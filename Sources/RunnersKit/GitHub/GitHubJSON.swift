import FP
import Foundation

/// GitHub's JSON: snake_case keys (spelled out in each model's `CodingKeys`), ISO 8601 dates.
public enum GitHubJSON {
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, GitHubError> {
        Result { try decoder.decode(type, from: data) }
            .mapError { .decoding(String(describing: $0)) }
    }

    public static func encode<T: Encodable>(_ value: T) -> Result<String, GitHubError> {
        Result { try encoder.encode(value) }
            .map { String(decoding: $0, as: UTF8.self) }
            .mapError { .encoding(String(describing: $0)) }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
