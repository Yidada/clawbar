import XCTest
@testable import Clawbar

final class HermesInstallerTests: XCTestCase {
    // MARK: parseVersion

    func testParseVersionExtractsSemanticVersion() {
        XCTAssertEqual(HermesInstaller.parseVersion("Hermes Agent v1.2.3"), "1.2.3")
    }

    func testParseVersionExtractsPrereleaseSuffix() {
        XCTAssertEqual(HermesInstaller.parseVersion("Hermes Agent v1.2.3-beta.4"), "1.2.3")
    }

    func testParseVersionReturnsNilWhenNoMatch() {
        XCTAssertNil(HermesInstaller.parseVersion("Hermes Agent (development build)"))
    }

    // MARK: parseDefaultModel

    func testParseDefaultModelInlineString() {
        XCTAssertEqual(HermesInstaller.parseDefaultModel("model: gpt-4o-mini\n"), "gpt-4o-mini")
    }

    func testParseDefaultModelStripsDoubleQuotes() {
        XCTAssertEqual(HermesInstaller.parseDefaultModel("model: \"anthropic/claude-opus-4.6\"\n"), "anthropic/claude-opus-4.6")
    }

    func testParseDefaultModelStripsSingleQuotes() {
        XCTAssertEqual(HermesInstaller.parseDefaultModel("model: 'gpt-4o'\n"), "gpt-4o")
    }

    func testParseDefaultModelNestedDefault() {
        let yaml = """
        provider: openrouter
        model:
          default: openai/gpt-4o
          fallback: openai/gpt-4o-mini
        """
        XCTAssertEqual(HermesInstaller.parseDefaultModel(yaml), "openai/gpt-4o")
    }

    func testParseDefaultModelIgnoresComments() {
        let yaml = "# comment\nmodel: gpt-4o # trailing comment\n"
        XCTAssertEqual(HermesInstaller.parseDefaultModel(yaml), "gpt-4o")
    }

    func testParseDefaultModelReturnsNilWhenAbsent() {
        XCTAssertNil(HermesInstaller.parseDefaultModel("provider: openrouter\n"))
    }

    func testParseDefaultModelStopsAtSiblingTopLevelKey() {
        let yaml = """
        model:
        provider: openrouter
        """
        XCTAssertNil(HermesInstaller.parseDefaultModel(yaml))
    }

    // MARK: collectStatusSnapshot — mock runner

    func testCollectStatusSnapshotReportsNotInstalledWhenHermesAndUVMissing() {
        let runner: HermesInstaller.CommandRunner = { executable, arguments, _, _ in
            XCTAssertEqual(executable, "/bin/zsh")
            XCTAssertEqual(arguments.first, "-lc")
            return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
        }
        let snapshot = HermesInstaller.collectStatusSnapshot(
            environment: [:],
            runCommand: runner,
            configReader: { _ in nil },
            configURL: URL(fileURLWithPath: "/tmp/none.yaml")
        )

        XCTAssertFalse(snapshot.isInstalled)
        XCTAssertNil(snapshot.hermesBinaryPath)
        XCTAssertNil(snapshot.uvBinaryPath)
        XCTAssertNil(snapshot.runtimeVersion)
        XCTAssertNil(snapshot.defaultModel)
    }

    func testCollectStatusSnapshotReportsInstalledWithVersionAndModel() {
        let runner: HermesInstaller.CommandRunner = { executable, arguments, _, _ in
            // Detect: command -v <name>
            if arguments.first == "-lc", let cmd = arguments.dropFirst().first {
                if cmd == "command -v uv" {
                    return OpenClawChannelCommandResult(output: "/opt/homebrew/bin/uv\n", exitStatus: 0, timedOut: false)
                }
                if cmd == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/Users/x/.local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
            }
            // Version
            if executable.hasSuffix("/hermes"), arguments == ["--version"] {
                return OpenClawChannelCommandResult(output: "Hermes Agent v0.5.1\n", exitStatus: 0, timedOut: false)
            }
            return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
        }
        let snapshot = HermesInstaller.collectStatusSnapshot(
            environment: [:],
            runCommand: runner,
            configReader: { _ in "model: openrouter/anthropic/claude-opus-4.6\n" },
            configURL: URL(fileURLWithPath: "/tmp/config.yaml")
        )

        XCTAssertTrue(snapshot.isInstalled)
        XCTAssertEqual(snapshot.hermesBinaryPath, "/Users/x/.local/bin/hermes")
        XCTAssertEqual(snapshot.uvBinaryPath, "/opt/homebrew/bin/uv")
        XCTAssertEqual(snapshot.runtimeVersion, "0.5.1")
        XCTAssertEqual(snapshot.defaultModel, "openrouter/anthropic/claude-opus-4.6")
    }

    // MARK: composeSnapshot

    func testComposeSnapshotMarksProviderAsHealthyWhenModelPresent() {
        let snapshot = HermesStatusSnapshot(
            isInstalled: true,
            hermesBinaryPath: "/usr/local/bin/hermes",
            uvBinaryPath: "/opt/homebrew/bin/uv",
            runtimeVersion: "0.5.1",
            defaultModel: "openai/gpt-4o"
        )
        let health = HermesInstaller.composeSnapshot(snapshot, configURL: URL(fileURLWithPath: "/tmp/config.yaml"))

        XCTAssertEqual(health.runtimeVersion, "0.5.1")
        XCTAssertEqual(health.dimensions.count, 2)
        let provider = health.dimensions.first { $0.dimension == .provider }
        XCTAssertEqual(provider?.level, .healthy)
        XCTAssertEqual(provider?.summary, "openai/gpt-4o")
    }

    func testComposeSnapshotMarksProviderAsWarningWhenInstalledWithoutModel() {
        let snapshot = HermesStatusSnapshot(
            isInstalled: true,
            hermesBinaryPath: "/usr/local/bin/hermes",
            uvBinaryPath: "/opt/homebrew/bin/uv",
            runtimeVersion: "0.5.1",
            defaultModel: nil
        )
        let health = HermesInstaller.composeSnapshot(snapshot, configURL: URL(fileURLWithPath: "/tmp/config.yaml"))
        let provider = health.dimensions.first { $0.dimension == .provider }
        XCTAssertEqual(provider?.level, .warning)
    }

    func testComposeSnapshotMarksDimensionsAsUnknownWhenUninstalled() {
        let snapshot = HermesStatusSnapshot(
            isInstalled: false,
            hermesBinaryPath: nil,
            uvBinaryPath: nil,
            runtimeVersion: nil,
            defaultModel: nil
        )
        let health = HermesInstaller.composeSnapshot(snapshot, configURL: URL(fileURLWithPath: "/tmp/config.yaml"))
        XCTAssertEqual(health.overallLevel, .unknown)
        XCTAssertNil(health.runtimeVersion)
    }

    // MARK: refreshStatus integration with injected dependencies

    @MainActor
    func testRefreshStatusWiresSnapshotIntoPublishedState() async {
        let runner: HermesInstaller.CommandRunner = { executable, arguments, _, _ in
            if arguments.first == "-lc", let cmd = arguments.dropFirst().first {
                if cmd == "command -v uv" {
                    return OpenClawChannelCommandResult(output: "/opt/homebrew/bin/uv\n", exitStatus: 0, timedOut: false)
                }
                if cmd == "command -v hermes" {
                    return OpenClawChannelCommandResult(output: "/Users/x/.local/bin/hermes\n", exitStatus: 0, timedOut: false)
                }
            }
            if executable.hasSuffix("/hermes"), arguments == ["--version"] {
                return OpenClawChannelCommandResult(output: "Hermes Agent v0.7.0\n", exitStatus: 0, timedOut: false)
            }
            return OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
        }
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-test"),
            runCommand: runner,
            configReader: { _ in "model: gpt-4o\n" }
        )

        await installer.refreshStatus(force: true)

        XCTAssertTrue(installer.isInstalled)
        XCTAssertEqual(installer.hermesVersion, "0.7.0")
        XCTAssertEqual(installer.defaultModel, "gpt-4o")
        XCTAssertNotNil(installer.healthSnapshot)
    }

    @MainActor
    func testRefreshStatusReflectsMissingHermes() async {
        let runner: HermesInstaller.CommandRunner = { _, _, _, _ in
            OpenClawChannelCommandResult(output: "", exitStatus: 1, timedOut: false)
        }
        let installer = HermesInstaller(
            refreshInterval: 0,
            homeOverride: URL(fileURLWithPath: "/tmp/hermes-test"),
            runCommand: runner,
            configReader: { _ in nil }
        )

        await installer.refreshStatus(force: true)

        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.hermesVersion)
        XCTAssertNil(installer.defaultModel)
    }
}
