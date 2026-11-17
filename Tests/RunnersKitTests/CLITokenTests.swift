import Testing

@testable import RunnersKit

@Suite("Tokens from command line clients")
struct CLITokenTests {
    @Test("gives what the command prints, trimmed")
    func printed() async {
        let token = await CLIToken("printf", ["  tok-123\n"], hint: "set TOKEN").token()
        #expect(token == .success("tok-123"))
    }

    @Test("fails when the command prints nothing")
    func nothing() async {
        let token = await CLIToken("echo", hint: "set TOKEN").token()
        #expect(token == .failure(.tokenUnavailable("`echo` printed nothing; set TOKEN")))
    }

    @Test("fails with the exit code and the first line the command wrote to standard error")
    func exited() async {
        let script = "echo >&2; echo '  not signed in  ' >&2; echo more >&2; exit 4"
        let token = await CLIToken("sh", ["-c", script], hint: "set TOKEN").token()
        #expect(
            token
                == .failure(
                    .tokenUnavailable("`sh -c \(script)` exited with 4: not signed in; set TOKEN")
                )
        )
    }

    @Test("fails with the exit code alone when the command wrote no error")
    func exitedQuietly() async {
        let token = await CLIToken("sh", ["-c", "exit 1"], hint: "set TOKEN").token()
        #expect(token == .failure(.tokenUnavailable("`sh -c exit 1` exited with 1; set TOKEN")))
    }

    @Test("fails when a signal stops the command")
    func signaled() async {
        let token = await CLIToken("sh", ["-c", "kill -9 $$"], hint: "set TOKEN").token()
        #expect(
            token
                == .failure(
                    .tokenUnavailable("`sh -c kill -9 $$` was stopped by signal 9; set TOKEN")
                )
        )
    }

    @Test("says when the command is not installed")
    func notInstalled() async {
        let token = await CLIToken(
            "runners-test-no-such-cli",
            ["auth", "token"],
            hint: "set TOKEN"
        )
        .token()
        #expect(
            token
                == .failure(
                    .tokenUnavailable(
                        "`runners-test-no-such-cli` is not installed or not on PATH; set TOKEN"
                    )
                )
        )
    }

    @Test("fails, without waiting for more, when the command prints more than a token")
    func tooMuch() async {
        let script = "yes | head -c 100000"
        let token = await CLIToken("sh", ["-c", script], hint: "set TOKEN").token()
        #expect(
            token
                == .failure(
                    .tokenUnavailable(
                        "`sh -c \(script)` printed more than \(CLIToken.outputLimit) bytes; set TOKEN"
                    )
                )
        )
    }

    @Test("asks gh for the token of the API's host")
    func gitHub() {
        let hint = "set GH_TOKEN or GITHUB_TOKEN, or run `gh auth login`"
        #expect(GHCLI.client() == CLIToken("gh", ["auth", "token"], hint: hint))
        #expect(
            GHCLI.client(hostname: "ghe.example.com")
                == CLIToken("gh", ["auth", "token", "--hostname", "ghe.example.com"], hint: hint)
        )
    }
}
