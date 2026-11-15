import ProgramStatus

/// Sends reports to the controlling terminal, when that is turned on. Reporting is
/// best-effort: without a terminal, or with one that does not know the protocol, nothing
/// shows and nothing fails.
struct TerminalStatus: Sendable {
    let reporter: ProgramStatusReporter?

    init(enabled: Bool, reporter: ProgramStatusReporter = ProgramStatusReporter(app: "runners")) {
        self.reporter = enabled ? reporter : nil
    }

    func send(_ report: StatusReport) {
        send([report])
    }

    func send(_ reports: [StatusReport]) {
        guard let reporter else { return }
        for report in reports {
            reporter.send(report)
        }
    }
}
