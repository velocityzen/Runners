import FP
import Foundation
import Testing

@testable import RunnersKit

@Suite("AWS mapping")
struct AWSMappingTests {
    let region = AWSFixtures.region

    // MARK: - Regions and endpoints

    @Test("takes region names, and nothing else")
    func regions() {
        for name in ["us-east-1", "us-gov-west-1", "ap-southeast-2", "cn-north-1"] {
            #expect(AWSRegion(name)?.name == name)
        }
        for name in ["", "US-EAST-1", "us-east", "useast1", "us-east-1a", "-east-1", "us--1"] {
            #expect(AWSRegion(name) == nil)
        }
    }

    @Test("reads the region from a CodeBuild endpoint, FIPS and China ones too")
    func endpoints() {
        #expect(region.codeBuildEndpoint == AWSFixtures.endpoint)
        #expect(
            AWSRegion("cn-north-1")?.codeBuildEndpoint.absoluteString
                == "https://codebuild.cn-north-1.amazonaws.com.cn"
        )
        let regions = [
            "https://codebuild.us-east-1.amazonaws.com": "us-east-1",
            "https://codebuild-fips.us-gov-west-1.amazonaws.com/": "us-gov-west-1",
            "https://codebuild.cn-north-1.amazonaws.com.cn": "cn-north-1",
        ]
        for (url, name) in regions {
            #expect(AWSRegion(codeBuildEndpoint: Fixtures.url(url))?.name == name)
        }
        for url in [
            "https://codebuild.amazonaws.com", "https://example.com", "http://localhost:4566",
        ] {
            #expect(AWSRegion(codeBuildEndpoint: Fixtures.url(url)) == nil)
        }
    }

    // MARK: - Credentials

    @Test("carry credentials as credential_process JSON, and keep the secret out of logs")
    func credentials() throws {
        let keys = AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret", sessionToken: "s")
        #expect(try AWSCredentials.from(token: keys.token).get() == keys)
        #expect(
            keys.token
                == #"{"AccessKeyId":"AKID","SecretAccessKey":"secret","SessionToken":"s","Version":1}"#
        )
        #expect(!"\(keys)".contains("secret"))

        let printed = """
            {"Version": 1, "AccessKeyId": "ASIA", "SecretAccessKey": "x", "SessionToken": "t",
             "Expiration": "2026-11-17T18:00:00+00:00"}
            """
        #expect(
            try AWSCredentials.from(token: printed).get()
                == AWSCredentials(accessKeyID: "ASIA", secretAccessKey: "x", sessionToken: "t")
        )
        #expect(AWSCredentials.from(token: #"{"AccessKeyId":"A"}"#).isFailure)
    }

    @Test("takes the key pair from its settings, both halves or neither")
    func tokenSettings() throws {
        let aws = AWSProvider()
        func token(_ values: [String: String]) -> Result<String?, RunnersError> {
            aws.token { settings in settings.lazy.compactMap { values[$0.name] }.first }
        }
        #expect(try token([:]).get() == nil)
        let both = try #require(
            try token([
                "aws.access_key_id": "AKID", "aws.secret_access_key": "secret",
                "aws.session_token": "s",
            ])
            .get()
        )
        #expect(
            try AWSCredentials.from(token: both).get()
                == AWSCredentials(accessKeyID: "AKID", secretAccessKey: "secret", sessionToken: "s")
        )
        #expect(
            token(["aws.access_key_id": "AKID"])
                == .failure(
                    .configuration(
                        "set both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or neither"
                    )
                )
        )
    }

    @Test("reads a region setting as its endpoint, and takes project names for --repo")
    func providerSettings() {
        let aws = AWSProvider()
        #expect(
            aws.apiURL("eu-west-1", from: aws.apiURLSettings[0])?.host()
                == "codebuild.eu-west-1.amazonaws.com"
        )
        #expect(aws.apiURL("Ireland", from: aws.apiURLSettings[0]) == nil)
        #expect(aws.isRepositoryName("gh-runner_2"))
        #expect(!aws.isRepositoryName("octo/app"))
        #expect(!aws.isRepositoryName("-runner"))
        #expect(!aws.isRepositoryName("r"))
        // CodeBuild's model caps a project name at 150 characters.
        #expect(aws.isRepositoryName(String(repeating: "r", count: 150)))
        #expect(!aws.isRepositoryName(String(repeating: "r", count: 151)))
        #expect(GitHubProvider().isRepositoryName("octo/app"))
        #expect(!GitHubProvider().isRepositoryName("runner"))
    }

    // MARK: - Projects

    @Test("tells runner projects by their webhook, and how long their builds can go on")
    func projects() {
        #expect(AWSFixtures.project("runner").isRunnerProject)
        #expect(!AWSFixtures.project("plain", runner: false).isRunnerProject)
        #expect(AWSFixtures.project("default").lifetime == 555 * 60)
        #expect(AWSFixtures.project("short", timeout: 30, queuedTimeout: 15).lifetime == 60 * 60)
        #expect(
            AWSFixtures.project("runner").repository(in: region).webURL.absoluteString
                == "https://us-east-1.console.aws.amazon.com/codesuite/codebuild/123456789012/"
                + "projects/runner/history?region=us-east-1"
        )
    }

    // MARK: - Builds

    @Test("counts a build queued until its runner is up, then running")
    func phases() {
        let statuses = [
            "SUBMITTED": RunStatus.queued, "QUEUED": .queued, "PROVISIONING": .queued,
            "DOWNLOAD_SOURCE": .running, "BUILD": .running, "FINALIZING": .running,
        ]
        for (phase, status) in statuses {
            #expect(AWSFixtures.build("runner", 1, phase: phase).status == status)
        }
        #expect(RunStatus(codeBuildPhase: nil) == .queued)
    }

    @Test("ends a finished build as its status says")
    func conclusions() {
        let conclusions = [
            "SUCCEEDED": Conclusion.success, "FAILED": .failure, "FAULT": .failure,
            "TIMED_OUT": .timedOut, "STOPPED": .cancelled,
        ]
        for (status, conclusion) in conclusions {
            let build = AWSFixtures.build("runner", 1, phase: "COMPLETED", status: status)
            #expect(build.status == .completed)
            #expect(build.conclusion == conclusion)
        }
        #expect(AWSFixtures.build("runner", 1).conclusion == nil)
    }

    @Test("maps a build to a run of its project, and to one job on its compute")
    func build() {
        let build = AWSFixtures.build("runner", 7, phase: "BUILD", minutesAgo: 10)
        let run = build.run(in: region)
        #expect(run.id == "runner:uuid-7")
        #expect(run.name == "runner")
        #expect(run.number == 7)
        #expect(run.title == "octo/app")
        #expect(run.branch == "main")
        #expect(run.commit == "0123456789abcdef0123456789abcdef01234567")
        #expect(run.trigger == "webhook")
        #expect(run.actor == nil)
        #expect(run.status == .running)
        #expect(run.createdAt == Fixtures.minutesAgo(10))
        // DOWNLOAD_SOURCE, the fourth phase, starts three minutes in.
        #expect(run.startedAt == Fixtures.minutesAgo(7))
        #expect(
            run.webURL.absoluteString
                == "https://us-east-1.console.aws.amazon.com/codesuite/codebuild/123456789012/"
                + "projects/runner/build/runner%3Auuid-7/?region=us-east-1"
        )

        let job = build.job(in: region)
        #expect(job.name == "BUILD_GENERAL1_SMALL")
        #expect(job.labels == ["LINUX_CONTAINER"])
        #expect(job.runner == "amazonlinux-x86_64-standard:5.0")
        #expect(job.currentStep == "build")
        #expect(job.startedAt == run.startedAt)
    }

    @Test("names who started a build, and drops a commit given as the branch")
    func initiators() {
        let byUser = AWSFixtures.build("runner", 1, sourceVersion: "feature", initiator: "alice")
        #expect(byUser.run(in: region).actor == "alice")
        #expect(byUser.run(in: region).trigger == nil)
        #expect(byUser.run(in: region).branch == "feature")
        let byPipeline = AWSFixtures.build("runner", 2, initiator: "codepipeline/release")
        #expect(byPipeline.run(in: region).trigger == "codepipeline")
        let atCommit = AWSFixtures.build(
            "runner",
            3,
            sourceVersion: "0123456789abcdef0123456789abcdef01234567"
        )
        #expect(atCommit.run(in: region).branch == nil)
    }

    @Test("names a fleet by its ARN, and a phase in words")
    func fleets() {
        #expect(
            AWSARN.resourceName("arn:aws:codebuild:us-east-1:1:fleet/big-arm:uuid") == "big-arm"
        )
        #expect(AWSARN.account("arn:aws:codebuild:us-east-1:123:project/p") == "123")
        #expect(AWSARN.account("not-an-arn") == nil)
        #expect(RunStatus.codeBuildPhrase("DOWNLOAD_SOURCE") == "download source")
    }

    // MARK: - Errors

    @Test("reads AWS errors by their type, most of which come with a 400")
    func errors() {
        func error(_ status: Int, _ body: String, headers: [String: String] = [:]) -> RunnersError {
            RunnersError(aws: .raw(status, body, headers: headers))
        }
        #expect(
            error(400, #"{"__type":"ThrottlingException","message":"Rate exceeded"}"#)
                == .throttled(retryAfter: .seconds(1))
        )
        #expect(
            error(
                400,
                #"{"__type":"com.amazon.coral.service#ExpiredTokenException","message":"expired"}"#
            ) == .unauthorized("expired")
        )
        #expect(
            error(400, #"{"__type":"AccessDeniedException","Message":"not allowed"}"#)
                == .forbidden("not allowed")
        )
        #expect(
            error(400, "", headers: ["X-Amzn-ErrorType": "ResourceNotFoundException:http://x/"])
                == .notFound("ResourceNotFoundException")
        )
        #expect(
            error(400, #"{"__type":"InvalidInputException","message":"bad token"}"#)
                == .unexpectedStatus(400, message: "InvalidInputException: bad token")
        )
        #expect(error(503, "unavailable") == .server(status: 503, message: "unavailable"))
        #expect(error(503, "unavailable").isTransient)
    }
}
