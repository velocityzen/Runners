import Foundation
import RunnersKit
import Testing

@testable import runners

@Suite("Settings")
struct SettingsTests {
    @Test("falls back to defaults")
    func defaults() async throws {
        let settings = try await ConfigFixture().settings().get()
        #expect(settings.provider == .github)
        #expect(settings.apiURL == GitHubService.defaultBaseURL)
        #expect(settings.token == nil)
        #expect(settings.query == StatusQuery(target: .authenticatedUser))
        #expect(!settings.showsPassedJobs)
        #expect(settings.interval == 15)
        #expect(settings.colored)
    }

    @Test("reads every setting from the config")
    func configured() async throws {
        let fixture = try ConfigFixture()
        try fixture.local(
            """
            provider=GitLab
            owner=my-group
            status=running
            jobs=false
            all_jobs=true
            forks=on
            concurrency=4
            interval=60
            color=false
            gitlab.host=gitlab.example.com
            gitlab.token=glpat-file
            """
        )
        let settings = try await fixture.settings().get()
        #expect(settings.provider == .gitlab)
        #expect(settings.apiURL.absoluteString == "https://gitlab.example.com/api/v4")
        #expect(settings.token == "glpat-file")
        #expect(
            settings.query
                == StatusQuery(
                    target: .owner("my-group"),
                    statuses: [.running],
                    includeJobs: false,
                    includeForks: true,
                    concurrency: 4
                )
        )
        #expect(settings.showsPassedJobs)
        #expect(settings.interval == 60)
        #expect(!settings.colored)
    }

    @Test("lets the command line win over the config")
    func overrides() async throws {
        let fixture = try ConfigFixture()
        try fixture.local(
            "provider=gitlab\nowner=octo\nstatus=running\njobs=false\nconcurrency=4\ninterval=60"
        )
        var given = Overrides()
        given.provider = .github
        given.repositories = ["octo/app"]
        given.statuses = [.queued]
        given.jobs = true
        given.concurrency = 8
        given.interval = 5
        given.apiURL = "https://ghe.example.com/api/v3"
        let settings = try await fixture.settings(given).get()
        #expect(settings.provider == .github)
        #expect(settings.apiURL.absoluteString == "https://ghe.example.com/api/v3")
        #expect(
            settings.query
                == StatusQuery(
                    target: .repositories(["octo/app"]),
                    statuses: [.queued],
                    concurrency: 8
                )
        )
        #expect(settings.interval == 5)
    }

    @Test("takes owner and repos together from the first source that sets either")
    func targetGroup() async throws {
        let fixture = try ConfigFixture()
        try fixture.global("repos=octo/app")
        try fixture.local("owner=octo")
        #expect(try await fixture.settings().get().query.target == .owner("octo"))
    }

    @Test("rejects owner and repos in the same source")
    func targetConflict() async throws {
        let fixture = try ConfigFixture()
        try fixture.local("owner=octo\nrepos=octo/app")
        let problem = try #require(await fixture.settings().configurationProblem)
        #expect(problem == "set owner (RUNNERS_OWNER) or repos (RUNNERS_REPOS), not both")
    }

    @Test(
        "names the setting a bad value came from",
        arguments: [
            ("RUNNERS_PROVIDER", "bitbucket", "provider (RUNNERS_PROVIDER)"),
            ("RUNNERS_CONCURRENCY", "64", "concurrency (RUNNERS_CONCURRENCY)"),
            ("RUNNERS_INTERVAL", "soon", "interval (RUNNERS_INTERVAL)"),
            ("RUNNERS_JOBS", "maybe", "jobs (RUNNERS_JOBS)"),
            ("RUNNERS_STATUS", "running,done", "status (RUNNERS_STATUS) is \"done\""),
            ("RUNNERS_REPOS", "app", "repos (RUNNERS_REPOS) is \"app\""),
            ("GITHUB_API_URL", "not a url", "github.api_url (GITHUB_API_URL)"),
        ]
    )
    func invalid(name: String, value: String, expected: String) async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [name: value]
        let problem = try #require(await fixture.settings().configurationProblem)
        #expect(problem.hasPrefix(expected))
    }

    @Test("prefers a token in the environment over one in a file")
    func tokenPrecedence() async throws {
        let fixture = try ConfigFixture()
        try fixture.global("github.token=from-file")
        fixture.environment = ["GITHUB_TOKEN": "from-environment"]
        #expect(try await fixture.settings().get().token == "from-environment")
    }

    @Test("prefers GH_TOKEN over GITHUB_TOKEN, and GITLAB_TOKEN over GITLAB_ACCESS_TOKEN")
    func tokenAliases() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "GITHUB_TOKEN": "github", "GH_TOKEN": "gh",
            "GITLAB_ACCESS_TOKEN": "access", "GITLAB_TOKEN": "gitlab",
        ]
        #expect(try await fixture.settings().get().token == "gh")
        var given = Overrides()
        given.provider = .gitlab
        #expect(try await fixture.settings(given).get().token == "gitlab")
    }

    @Test("prefers CI_API_V4_URL over GITLAB_HOST")
    func gitLabURL() async throws {
        let fixture = try ConfigFixture()
        fixture.environment = [
            "RUNNERS_PROVIDER": "gitlab",
            "GITLAB_HOST": "gitlab.example.com",
            "CI_API_V4_URL": "https://ci.example.com/api/v4",
        ]
        #expect(
            try await fixture.settings().get().apiURL.absoluteString
                == "https://ci.example.com/api/v4"
        )
    }

    @Test("colors a terminal unless NO_COLOR is set; the config and command line override both")
    func color() async throws {
        let fixture = try ConfigFixture()
        #expect(try await !fixture.settings(isTerminal: false).get().colored)
        fixture.environment = ["NO_COLOR": "1"]
        #expect(try await !fixture.settings().get().colored)
        try fixture.local("color=true")
        #expect(try await fixture.settings().get().colored)
        var given = Overrides()
        given.color = false
        #expect(try await !fixture.settings(given).get().colored)
    }
}
