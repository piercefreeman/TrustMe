import Foundation
import Testing
@testable import TrustMe

private final class BundleAnchor {}

/// The TrustMeProbeHost executable, built next to the test bundle.
private var probeHost: URL {
    Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent().appendingPathComponent("TrustMeProbeHost")
}

private func runHost(environment: [String: String]) throws -> String {
    let process = Process()
    process.executableURL = probeHost
    process.environment = environment
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    process.waitUntilExit()
    return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

@Suite("Fresh-process TCC probe")
struct ProbeTests {
    @Test("Linking TrustMe installs the probe: it answers before main runs")
    func answersBeforeMain() throws {
        let output = try runHost(environment: ["TRUSTME_TCC_PROBE": "kTCCServiceAccessibility"])
        #expect(output.hasPrefix("TRUSTME_PROBE:"))
        #expect(!output.contains("started normally"))
    }

    @Test("Without the variable the program runs normally")
    func dormantByDefault() throws {
        let output = try runHost(environment: [:])
        #expect(output.contains("started normally"))
        #expect(!output.contains("TRUSTME_PROBE"))
    }

    @Test("Programs that don't link TrustMe produce no answer")
    func ignoresOtherPrograms() {
        #expect(FreshProbe.run(service: "kTCCServiceAccessibility", executable: URL(fileURLWithPath: "/usr/bin/true")) == nil)
    }

    @Test("A program that never exits is killed at the timeout")
    func timesOut() {
        let start = Date()
        let result = FreshProbe.run(service: "kTCCServiceAccessibility",
                                    executable: URL(fileURLWithPath: "/usr/bin/yes"), timeout: 0.5)
        #expect(result == nil)
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test("Never re-executes a process that isn't an app bundle")
    func skipsNonApps() {
        // The test runner isn't a .app, so this must not spawn it again.
        #expect(FreshProbe.status("Accessibility") == nil)
    }
}
