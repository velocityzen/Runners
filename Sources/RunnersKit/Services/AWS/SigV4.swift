import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#else
    import Crypto
#endif

/// Signs requests with AWS Signature Version 4, as every AWS API asks.
///
/// It signs the host, the content type and every `X-Amz-` header, and the body. See
/// https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_sigv-create-signed-request.html
struct SigV4: Sendable {
    let credentials: AWSCredentials
    let region: String
    /// The service's signing name: `codebuild`.
    let service: String

    /// The request with `X-Amz-Date`, the session token if there is one, and `Authorization`.
    func sign(_ request: HTTPRequest, at date: Date) -> HTTPRequest {
        var signed = request
        let time = Self.timestamp(date)
        signed.headers["X-Amz-Date"] = time
        if let sessionToken = credentials.sessionToken {
            signed.headers["X-Amz-Security-Token"] = sessionToken
        }
        let headers = Self.canonicalHeaders(of: signed)
        let signedHeaders = headers.map(\.name).joined(separator: ";")
        let canonicalRequest = [
            request.method,
            Self.canonicalPath(of: request.url),
            Self.canonicalQuery(of: request.url),
            headers.map { "\($0.name):\($0.value)\n" }.joined(),
            signedHeaders,
            Self.hex(SHA256.hash(data: request.body ?? Data())),
        ]
        .joined(separator: "\n")
        let day = String(time.prefix(8))
        let scope = "\(day)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256", time, scope,
            Self.hex(SHA256.hash(data: Data(canonicalRequest.utf8))),
        ]
        .joined(separator: "\n")
        let signature = HMAC<SHA256>.authenticationCode(
            for: Data(stringToSign.utf8),
            using: signingKey(day: day)
        )
        signed.headers["Authorization"] =
            "AWS4-HMAC-SHA256 Credential=\(credentials.accessKeyID)/\(scope), "
            + "SignedHeaders=\(signedHeaders), Signature=\(Self.hex(signature))"
        return signed
    }

    /// The key for one day, region and service, derived from the secret key.
    func signingKey(day: String) -> SymmetricKey {
        [day, region, service, "aws4_request"].reduce(
            SymmetricKey(data: Data("AWS4\(credentials.secretAccessKey)".utf8))
        ) { key, part in
            SymmetricKey(
                data: Data(HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: key))
            )
        }
    }

    // MARK: - Canonical form

    /// `20150830T123600Z`
    static func timestamp(_ date: Date) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(
                dateSeparator: .omitted,
                timeSeparator: .omitted,
                timeZone: .gmt
            )
        )
    }

    /// The host, the content type and the `X-Amz-` headers, by lowercase name, with their
    /// values trimmed and inner runs of spaces made one.
    static func canonicalHeaders(of request: HTTPRequest) -> [(name: String, value: String)] {
        var headers = Dictionary(
            request.headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        .filter { name, _ in name == "content-type" || name.hasPrefix("x-amz-") }
        if let host = request.headers.first(where: { $0.key.lowercased() == "host" })?.value
            ?? host(of: request.url)
        {
            headers["host"] = host
        }
        return headers.map { (name: $0.key, value: normalized($0.value)) }
            .sorted { $0.name < $1.name }
    }

    /// The host as a `Host` header gives it: with the port, unless it is the scheme's own.
    static func host(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: true) else { return nil }
        let defaultPort = url.scheme == "http" ? 80 : 443
        return url.port.map { $0 == defaultPort ? host : "\(host):\($0)" } ?? host
    }

    static func normalized(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canonicalPath(of url: URL) -> String {
        let path = url.path(percentEncoded: true)
        return path.isEmpty ? "/" : path
    }

    /// The query's names and values, each encoded, in order by name and then value.
    static func canonicalQuery(of url: URL) -> String {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
            .map { (name: encode($0.name), value: encode($0.value ?? "")) }
            .sorted { ($0.name, $0.value) < ($1.name, $1.value) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "&")
    }

    /// Escapes everything but the unreserved characters, as SigV4 wants.
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func hex(_ bytes: some Sequence<UInt8>) -> String {
        let digits = Array("0123456789abcdef".utf8)
        var text: [UInt8] = []
        text.reserveCapacity(64)
        for byte in bytes {
            text.append(digits[Int(byte >> 4)])
            text.append(digits[Int(byte & 0x0F)])
        }
        return String(decoding: text, as: UTF8.self)
    }
}
