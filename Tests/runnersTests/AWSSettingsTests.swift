import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("AWS settings")
struct AWSSettingsTests {
    @Test("reads the key pair and the region from the environment, as the AWS CLI does")
    func environment() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "aws",
            "AWS_ACCESS_KEY_ID": "AKID",
            "AWS_SECRET_ACCESS_KEY": "secret",
            "AWS_SESSION_TOKEN": "session",
            "AWS_DEFAULT_REGION": "eu-west-1",
            "AWS_REGION": "eu-central-1",
        ]
        let settings = try await fixture.settings().get()
        #expect(settings.provider.id == "aws")
        #expect(settings.apiURL?.absoluteString == "https://codebuild.eu-central-1.amazonaws.com")
        let token = try #require(settings.token)
        #expect(
            try AWSCredentials.from(token: token).get()
                == AWSCredentials(
                    accessKeyID: "AKID",
                    secretAccessKey: "secret",
                    sessionToken: "session"
                )
        )
    }

    @Test("takes them from .runners too, and AWS_DEFAULT_REGION from the environment only")
    func files() async throws {
        let fixture = try ConfigFixture()
        try fixture.global("aws.access_key_id=AKID\naws.secret_access_key=secret")
        try fixture.local("provider=aws\naws.region=ap-southeast-2")
        let settings = try await fixture.settings().get()
        #expect(settings.apiURL?.host() == "codebuild.ap-southeast-2.amazonaws.com")
        #expect(
            try AWSCredentials.from(token: try #require(settings.token)).get().accessKeyID == "AKID"
        )
        try fixture.local("provider=aws\naws.default_region=ap-southeast-2")
        let problem = try #require(await fixture.settings().configurationProblem)
        #expect(problem.contains("unknown setting \"aws.default_region\""))
    }

    @Test("says what a region looks like, and leaves an unset one to the AWS CLI")
    func region() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = ["RUNNERS_PROVIDER": "aws", "AWS_REGION": "Ireland"]
        #expect(
            await fixture.settings().configurationProblem
                == "aws.region (AWS_REGION) is \"Ireland\", expected a region, such as us-east-1"
        )
        fixture.environment = ["RUNNERS_PROVIDER": "aws"]
        let settings = try await fixture.settings().get()
        #expect(settings.apiURL == nil)
        #expect(settings.token == nil)
    }

    @Test("takes CodeBuild project names for --repo, where GitHub takes full names")
    func repositoryNames() async throws {
        let fixture = try ConfigFixture()
        var given = Overrides()
        given.provider = "aws"
        given.repositories = ["gh-runner"]
        #expect(
            try await fixture.settings(given).get().query.target == .repositories(["gh-runner"])
        )
        given.repositories = ["octo/app"]
        #expect(
            await fixture.settings(given).configurationProblem
                == "--repo is \"octo/app\", expected a CodeBuild project name"
        )
        given.provider = nil
        #expect(try await fixture.settings(given).get().query.target == .repositories(["octo/app"]))
        try fixture.local("provider=aws\nrepos=octo/app")
        #expect(
            await fixture.settings().configurationProblem
                == "repos (RUNNERS_REPOS) is \"octo/app\", expected a CodeBuild project name"
        )
    }
}
