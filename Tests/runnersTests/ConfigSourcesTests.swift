import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Config sources")
struct ConfigSourcesTests {
    @Test("works with no files at all")
    func nothing() async throws {
        let config = try await ConfigFixture().config().get()
        #expect(config.sources.count == 4)
        #expect(config.text(.owner) == nil)
    }

    @Test("reads key=value lines from .runners, named as in the code")
    func keyValues() async throws {
        let fixture = try ConfigFixture()
        try fixture.local(
            """
            # my settings
            owner = octo
            status=running, queued
            all_jobs=yes

            concurrency=4
            github.token="from-file"
            github.api_url=https://ghe.example.com/api/v3?x=1
            """
        )
        let config = try await fixture.config().get()
        #expect(config.text(.owner) == "octo")
        #expect(config.list(.status) == ["running", "queued"])
        #expect(config.text(.allJobs) == "yes")
        #expect(config.text(.concurrency) == "4")
        #expect(config.text("github.token") == "from-file")
        #expect(config.text("github.api_url") == "https://ghe.example.com/api/v3?x=1")
    }

    @Test("lets a later line override an earlier one")
    func repeated() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner=first\nowner=second")
        #expect(try await fixture.config().get().text(.owner) == "second")
    }

    @Test(
        "rejects environment names and keys it does not know",
        arguments: ["RUNNERS_OWNER=octo", "GITHUB_TOKEN=x", "gh.token=x", "concurency=4"]
    )
    func unknown(line: String) async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner=octo\n\(line)")
        let problem = try #require(await fixture.config().configurationProblem)
        let name = String(line.prefix { $0 != "=" })
        #expect(
            problem.contains(
                ".runners:2: unknown setting \"\(name)\"; the settings are provider, owner, repos"
            )
        )
    }

    @Test("rejects a line without a value")
    func malformed() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner octo")
        let problem = try #require(await fixture.config().configurationProblem)
        #expect(problem.hasSuffix(".runners:1: expected key=value"))
    }

    @Test("reads a comma-separated list from the environment")
    func lists() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = ["RUNNERS_REPOS": "octo/app, octo/lib"]
        #expect(try await fixture.config().get().list(.repositories) == ["octo/app", "octo/lib"])
    }

    @Test("lets the environment win over .env, .env over .runners, and .runners over ~/.runners")
    func precedence() async throws {
        let fixture = try ConfigFixture()
        try fixture.global("concurrency=1\ninterval=10\nforks=true\nprovider=gitlab")
        try fixture.local("concurrency=2\ninterval=20\nforks=false")
        try fixture.dotEnv("RUNNERS_CONCURRENCY=3\nRUNNERS_INTERVAL=30\n")
        fixture.environment = ["RUNNERS_CONCURRENCY": "4"]
        let config = try await fixture.config().get()
        #expect(config.text(.concurrency) == "4")
        #expect(config.text(.interval) == "30")
        #expect(config.text(.forks) == "false")
        #expect(config.text(.provider) == "gitlab")
    }

    @Test("ignores blank values")
    func blank() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner=octo")
        fixture.environment = ["RUNNERS_OWNER": "  "]
        #expect(try await fixture.config().get().text(.owner) == "octo")
    }

    @Test("reads the --config file instead of ./.runners, relative to the working directory")
    func configFile() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner=local")
        try fixture.write("owner=chosen", to: fixture.project.appending(path: "ci.runners"))
        fixture.configFile = "ci.runners"
        #expect(try await fixture.config().get().text(.owner) == "chosen")
    }

    @Test("fails when the --config file is missing")
    func missingConfigFile() async throws {
        let fixture = try ConfigFixture()
        fixture.configFile = "nope.runners"
        let problem = try #require(await fixture.config().configurationProblem)
        #expect(problem.hasPrefix("no file at "))
        #expect(problem.hasSuffix("nope.runners"))
    }
}
