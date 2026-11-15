import Testing

@testable import runners

@Suite("Setting keys")
struct SettingKeyTests {
    @Test(
        "spells each key for the environment and for files",
        arguments: [
            (SettingKey.allJobs, "RUNNERS_ALL_JOBS", "all_jobs"),
            (.repositories, "RUNNERS_REPOS", "repos"),
            (.gitHubAPIURL, "GITHUB_API_URL", "github.api_url"),
            (.gitLabAccessToken, "GITLAB_ACCESS_TOKEN", "gitlab.access_token"),
            (.gitLabCIAPIURL, "CI_API_V4_URL", "ci.api_v4_url"),
            (.noColor, "NO_COLOR", "no_color"),
        ]
    )
    func spelling(key: SettingKey, environmentName: String, fileName: String) {
        #expect(key.environmentName == environmentName)
        #expect(key.fileName == fileName)
    }

    @Test("names both spellings when a value is wrong")
    func invalid() {
        let error = SettingKey.concurrency.invalid("lots", expected: "a number")
        #expect(
            error.localizedDescription
                == "Configuration: concurrency (RUNNERS_CONCURRENCY) is \"lots\", expected a number"
        )
    }
}
