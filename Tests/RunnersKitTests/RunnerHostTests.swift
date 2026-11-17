import Foundation
import Testing

@testable import RunnersKit

@Suite("Runner hosts")
struct RunnerHostTests {
    @Test(
        "tells each vendor's runners by the labels they answer to",
        arguments: [
            ("depot-ubuntu-24.04", RunnerHost.depot),
            ("Depot-macOS-26", .depot),
            ("blacksmith-4vcpu-ubuntu-2404", .blacksmith),
            ("warp-ubuntu-latest-x64-4x", .warpBuild),
            ("namespace-profile-default", .namespace),
            ("ubicloud", .ubicloud),
            ("ubicloud-standard-4-arm", .ubicloud),
            ("codebuild-gh-runner-123-1", .codeBuild),
        ]
    )
    func labels(_ label: String, _ host: RunnerHost) {
        #expect(RunnerHost(label: label) == host)
    }

    @Test("leaves GitHub's own runners and plain self-hosted ones alone")
    func others() {
        for label in ["ubuntu-latest", "macos-15", "self-hosted", "linux", "x64", "depot"] {
            #expect(RunnerHost(label: label) == nil)
        }
        #expect(RunnerHost(labels: ["self-hosted", "linux", "depot-ubuntu-24.04"]) == .depot)
        #expect(RunnerHost(labels: []) == nil)
    }

    @Test("names the vendor in the report, before the runner or the labels a job waits for")
    func report() {
        let jobs = [
            Fixtures.job(
                1,
                "build",
                .running,
                runner: "depot-runner-1",
                labels: ["depot-ubuntu-24.04"],
                step: "Compile"
            ),
            Fixtures.job(2, "test", .queued, labels: ["blacksmith-4vcpu-ubuntu-2404"]),
            Fixtures.job(3, "lint", .queued, labels: ["ubicloud-standard-4"]),
            Fixtures.job(4, "docs", .queued, labels: ["ubuntu-latest"]),
        ]
        #expect(
            TextReport(now: Fixtures.now).jobLines(jobs) == [
                "    ● build 2m 00s        Depot · depot-runner-1 → Compile",
                "    ○ test  queued 3m 00s Blacksmith · blacksmith-4vcpu-ubuntu-2404",
                "    ○ lint  queued 3m 00s Ubicloud · ubicloud-standard-4",
                "    ○ docs  queued 3m 00s ubuntu-latest",
            ]
        )
    }

    @Test("carries the vendor in the JSON")
    func json() throws {
        let job = Fixtures.job(1, "build", .queued, labels: ["depot-ubuntu-24.04"])
        let data = try JSONEncoder().encode(job)
        #expect(String(decoding: data, as: UTF8.self).contains(#""runner_host":"depot""#))
        #expect(try JSONDecoder().decode(Job.self, from: data) == job)
        #expect(Fixtures.job(2, "docs", .queued).runnerHost == nil)
    }
}
