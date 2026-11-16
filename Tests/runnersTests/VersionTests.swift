import ArgumentParser
import Testing

@testable import runners

@Suite("Version")
struct VersionTests {
    @Test("says dev in the repository; only the release workflow stamps a number")
    func dev() {
        #expect(Version.current == "dev")
    }

    @Test("--version prints the version and exits cleanly")
    func flag() {
        do {
            _ = try RunnersCommand.parseAsRoot(["--version"])
            Issue.record("--version parsed as a command")
        } catch {
            #expect(RunnersCommand.message(for: error) == Version.current)
            #expect(RunnersCommand.exitCode(for: error) == .success)
        }
    }
}
