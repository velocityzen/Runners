import FP
import FPRetry
import Foundation

/// Calls an AWS API that speaks JSON 1.1: each operation is a signed `POST /`, named in
/// `X-Amz-Target`, with JSON in and out. Transient failures, throttling among them, are
/// retried.
struct AWSJSONClient: Sendable {
    let endpoint: URL
    /// The operations' prefix: `CodeBuild_20161006`.
    let target: String
    let credentials: AWSCredentialsSource
    /// The region and service the requests are signed for: `us-east-1`, `codebuild`.
    let region: String
    let service: String
    let transport: any HTTPTransport
    let retryPolicy: RetryPolicy
    let now: @Sendable () -> Date

    /// Calls `operation` with `input`, and decodes its output.
    func call<Output: Decodable>(
        _ operation: String,
        _ input: some Encodable,
        as type: Output.Type = Output.self
    ) async -> Result<Output, RunnersError> {
        await Self.encode(input)
            .flatMapAsync { body in await send(operation, body: body) }
            .flatMap { Self.decode(type, from: $0.body) }
    }

    func send(_ operation: String, body: Data) async -> Result<HTTPResponse, RunnersError> {
        let request = HTTPRequest(
            method: "POST",
            url: endpoint,
            headers: [
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target": "\(target).\(operation)",
                "User-Agent": "Runners",
            ],
            body: body
        )
        return await withRetry(retryPolicy, while: \.isTransient, requestedDelay: \.retryAfter) {
            // Signed for each attempt, so a retry after a wait carries the time it is sent, and
            // the credentials current then.
            let now = now()
            return await credentials.current(at: now)
                .map { SigV4(credentials: $0, region: region, service: service) }
                .flatMapAsync { signer in await transport.send(signer.sign(request, at: now)) }
                .flatMap { $0.isSuccess ? .success($0) : .failure(RunnersError(aws: $0)) }
        }
    }

    static func encode(_ input: some Encodable) -> Result<Data, RunnersError> {
        Result { try JSONEncoder.sorted.encode(input) }
            .mapError { .encoding(String(describing: $0)) }
    }

    /// AWS sends times as seconds since 1970, with a fraction.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, RunnersError> {
        Result { try decoder.decode(type, from: data) }
            .mapError { .decoding(String(describing: $0)) }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

extension RunnersError {
    /// The error an AWS JSON 1.1 response means: by the error type it names, else by status.
    /// AWS answers most errors with 400, throttling and expired keys among them.
    init(aws response: HTTPResponse) {
        let error = AWSErrorBody(response)
        switch error.type {
            case "ThrottlingException", "Throttling", "ThrottledException",
                "TooManyRequestsException", "RequestLimitExceeded", "RequestThrottled",
                "RequestThrottledException":
                self = .throttled(retryAfter: .seconds(1))
            case "UnrecognizedClientException", "InvalidClientTokenId",
                "InvalidSignatureException", "SignatureDoesNotMatch", "IncompleteSignature",
                "MissingAuthenticationToken", "MissingAuthenticationTokenException",
                "ExpiredTokenException", "ExpiredToken", "AuthFailure":
                self = .unauthorized(error.message)
            case "AccessDeniedException", "AccessDenied":
                self = .forbidden(error.message)
            case "ResourceNotFoundException":
                self = .notFound(error.message)
            default:
                switch response.status {
                    case 401: self = .unauthorized(error.message)
                    case 403: self = .forbidden(error.message)
                    case 404: self = .notFound(error.message)
                    case 429: self = .throttled(retryAfter: .seconds(1))
                    case 500...: self = .server(status: response.status, message: error.message)
                    default:
                        self = .unexpectedStatus(
                            response.status,
                            message: [error.type, error.message].compact().joined(separator: ": ")
                        )
                }
        }
    }
}

/// The error in an AWS JSON 1.1 response: its type, from `__type` or the `X-Amzn-ErrorType`
/// header, and its message.
struct AWSErrorBody {
    /// The type without its namespace or URL: `ExpiredTokenException` for
    /// `com.amazon.coral.service#ExpiredTokenException`.
    let type: String?
    let message: String

    init(_ response: HTTPResponse) {
        let body = AWSJSONClient.decode(Body.self, from: response.body).getOrElse { _ in Body() }
        type = (body.type ?? response.header("x-amzn-errortype")).flatMap(Self.shortType)
        message =
            body.message ?? body.capitalMessage ?? type
            ?? String(decoding: response.body.prefix(200), as: UTF8.self)
    }

    static func shortType(_ raw: String) -> String? {
        raw.split(separator: "#").last
            .flatMap { $0.split(separator: ":").first }
            .map(String.init)
    }

    struct Body: Decodable {
        var type: String?
        var message: String?
        var capitalMessage: String?

        enum CodingKeys: String, CodingKey {
            case type = "__type"
            case message
            case capitalMessage = "Message"
        }
    }
}
