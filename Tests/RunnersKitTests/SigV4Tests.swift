import Foundation
import Testing

@testable import RunnersKit

@Suite("SigV4 signing")
struct SigV4Tests {
    /// The keys and time of AWS's published SigV4 test suite.
    let credentials = AWSCredentials(
        accessKeyID: "AKIDEXAMPLE",
        secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"
    )
    /// 2015-08-30T12:36:00Z
    let date = Date(timeIntervalSince1970: 1_440_938_160)

    func signed(
        _ request: HTTPRequest,
        service: String = "service",
        sessionToken: String? = nil
    ) -> HTTPRequest {
        let keys = AWSCredentials(
            accessKeyID: credentials.accessKeyID,
            secretAccessKey: credentials.secretAccessKey,
            sessionToken: sessionToken
        )
        return SigV4(credentials: keys, region: "us-east-1", service: service)
            .sign(request, at: date)
    }

    func authorization(_ scope: String, _ signedHeaders: String, _ signature: String) -> String {
        "AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20150830/us-east-1/\(scope)/aws4_request, "
            + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
    }

    @Test("signs a bare GET as the test suite's get-vanilla")
    func getVanilla() {
        let request = HTTPRequest(url: Fixtures.url("https://example.amazonaws.com/"))
        #expect(
            signed(request).headers["Authorization"]
                == authorization(
                    "service",
                    "host;x-amz-date",
                    "5fa00fa31553b73ebf1942676e86291e8372ff2a2260956d9b8aae1d763fbf31"
                )
        )
    }

    @Test("signs a bare POST as the test suite's post-vanilla")
    func postVanilla() {
        let request = HTTPRequest(
            method: "POST",
            url: Fixtures.url("https://example.amazonaws.com/")
        )
        #expect(
            signed(request).headers["Authorization"]
                == authorization(
                    "service",
                    "host;x-amz-date",
                    "5da7c1a2acd57cee7505fc6676e4e544621c30862966e37dddb68e92efbe5d6b"
                )
        )
    }

    @Test("signs the query and the content type, as in the IAM guide's example")
    func query() {
        let request = HTTPRequest(
            url: Fixtures.url("https://iam.amazonaws.com/?Version=2010-05-08&Action=ListUsers"),
            headers: ["Content-Type": "application/x-www-form-urlencoded; charset=utf-8"]
        )
        #expect(
            signed(request, service: "iam").headers["Authorization"]
                == authorization(
                    "iam",
                    "content-type;host;x-amz-date",
                    "5d672d79c15b13162d9279b0855cfba6789a8edb4c82c400e06b5924a6f2b5d7"
                )
        )
    }

    @Test("signs a CodeBuild call: its target, body and session token, not its user agent")
    func codeBuild() {
        let request = HTTPRequest(
            method: "POST",
            url: AWSFixtures.endpoint,
            headers: [
                "Content-Type": "application/x-amz-json-1.1",
                "X-Amz-Target": "CodeBuild_20161006.ListProjects",
                "User-Agent": "Runners",
            ],
            body: Data(#"{"sortBy":"NAME"}"#.utf8)
        )
        let signed = signed(request, service: "codebuild", sessionToken: "session-token")
        #expect(signed.headers["X-Amz-Date"] == "20150830T123600Z")
        #expect(signed.headers["X-Amz-Security-Token"] == "session-token")
        #expect(
            signed.headers["Authorization"]
                == authorization(
                    "codebuild",
                    "content-type;host;x-amz-date;x-amz-security-token;x-amz-target",
                    "a5cce4e0e099f3ec974f4b64c076693be3cd38209eebd72098ff80b66e220956"
                )
        )
    }

    @Test("writes the host with its port unless it is the scheme's own")
    func host() {
        #expect(SigV4.host(of: Fixtures.url("https://a.example.com/")) == "a.example.com")
        #expect(SigV4.host(of: Fixtures.url("https://a.example.com:443/")) == "a.example.com")
        #expect(SigV4.host(of: Fixtures.url("http://localhost:4566/")) == "localhost:4566")
    }

    @Test("collapses runs of spaces in header values")
    func normalized() {
        #expect(SigV4.normalized("  a   b  c ") == "a b c")
    }
}
