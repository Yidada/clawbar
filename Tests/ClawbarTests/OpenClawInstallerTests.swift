import XCTest
@testable import Clawbar

@MainActor
final class OpenClawInstallerTests: XCTestCase {
    func testInstallCommandMatchesOfficialNoOnboardFlow() {
        XCTAssertEqual(
            OpenClawInstaller.installCommand,
            "curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard"
        )
    }

    func testUninstallCommandMatchesNonInteractiveFullRemovalFlow() {
        XCTAssertEqual(
            OpenClawInstaller.uninstallCommand,
            "openclaw uninstall --all --yes --non-interactive && npm rm -g openclaw"
        )
    }

    func testParseDetectedBinaryPathReturnsTrimmedCommandPath() {
        XCTAssertEqual(
            OpenClawInstaller.parseDetectedBinaryPath("/opt/homebrew/bin/openclaw\n"),
            "/opt/homebrew/bin/openclaw"
        )
    }

    func testParseDetectedBinaryPathReturnsNilForEmptyOutput() {
        XCTAssertNil(OpenClawInstaller.parseDetectedBinaryPath("\n  \n"))
    }

    func testDisplayBinaryPathCollapsesHomePrefix() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            OpenClawInstaller.displayBinaryPath("\(homePath)/bin/openclaw"),
            "~/bin/openclaw"
        )
    }

    func testSummarizeStatusLineCompressesPluginWarning() {
        XCTAssertEqual(
            OpenClawInstaller.summarizeStatusLine("[plugins] plugins.allow is empty; discovered non-bundled plugins may auto-load: foo, bar"),
            "plugins.allow is empty; discovered non-bundled plugins."
        )
    }

    func testSummarizeStatusLineTruncatesLongGenericOutput() {
        let summary = OpenClawInstaller.summarizeStatusLine(String(repeating: "a", count: 120), maxLength: 20)
        XCTAssertEqual(summary, String(repeating: "a", count: 19) + "…")
    }

    func testShouldRefreshStatusReturnsTrueWithoutCache() {
        XCTAssertTrue(
            OpenClawInstaller.shouldRefreshStatus(
                force: false,
                isRefreshing: false,
                lastRefreshDate: nil,
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsFalseWhenCacheIsFresh() {
        XCTAssertFalse(
            OpenClawInstaller.shouldRefreshStatus(
                force: false,
                isRefreshing: false,
                lastRefreshDate: Date(timeIntervalSince1970: 90),
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsTrueWhenForced() {
        XCTAssertTrue(
            OpenClawInstaller.shouldRefreshStatus(
                force: true,
                isRefreshing: false,
                lastRefreshDate: Date(timeIntervalSince1970: 99),
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsFalseWhileRefreshIsInFlight() {
        XCTAssertFalse(
            OpenClawInstaller.shouldRefreshStatus(
                force: true,
                isRefreshing: true,
                lastRefreshDate: nil,
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testMakeStatusSnapshotUsesExcerptWhenStatusReturnsLines() {
        let snapshot = OpenClawInstaller.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandOutput: "\nstatus ok\nsecond line\n",
            timedOut: false
        )

        XCTAssertEqual(snapshot.title, "OpenClaw 已安装")
        XCTAssertEqual(snapshot.detail, "status 已返回最近状态。")
        XCTAssertEqual(snapshot.excerpt, "status ok")
        XCTAssertEqual(snapshot.binaryPath, "/opt/homebrew/bin/openclaw")
    }

    func testMakeStatusSnapshotReportsTimeoutWhenStatusDoesNotComplete() {
        let snapshot = OpenClawInstaller.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            commandOutput: "plugin warning",
            timedOut: true
        )

        XCTAssertEqual(snapshot.detail, "status 命令未在 3 秒内完成。")
        XCTAssertEqual(snapshot.excerpt, "plugin warning")
    }

    func testInstallationEnvironmentAddsCommonInteractivePaths() {
        let environment = OpenClawInstaller.installationEnvironment(base: [:])

        XCTAssertEqual(
            environment["PATH"],
            "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        )
    }

    func testOverrideParsesInstalledStateFromEnvironment() {
        let overrideState = OpenClawInstallerOverride.from(environment: [
            "CLAWBAR_TEST_OPENCLAW_STATE": "installed",
            "CLAWBAR_TEST_OPENCLAW_BINARY_PATH": "/opt/homebrew/bin/openclaw",
            "CLAWBAR_TEST_OPENCLAW_DETAIL": "status 已返回最近状态。",
            "CLAWBAR_TEST_OPENCLAW_EXCERPT": "plugins.allow is empty; discovered non-bundled plugins."
        ])

        guard case let .installed(snapshot)? = overrideState?.state else {
            return XCTFail("Expected installed override state")
        }

        XCTAssertEqual(snapshot.title, "OpenClaw 已安装")
        XCTAssertEqual(snapshot.detail, "status 已返回最近状态。")
        XCTAssertEqual(snapshot.excerpt, "plugins.allow is empty; discovered non-bundled plugins.")
        XCTAssertEqual(snapshot.binaryPath, "/opt/homebrew/bin/openclaw")
    }

    func testRefreshInstallationStatusUsesOverrideSnapshot() {
        let installer = OpenClawInstaller(
            overrideState: OpenClawInstallerOverride(
                state: .installed(
                    OpenClawStatusSnapshot(
                        title: "OpenClaw 已安装",
                        detail: "status 已返回最近状态。",
                        excerpt: "plugins.allow is empty; discovered non-bundled plugins.",
                        binaryPath: "/opt/homebrew/bin/openclaw"
                    )
                )
            ),
            autoStartTimer: false
        )

        installer.refreshInstallationStatus()

        XCTAssertTrue(installer.isInstalled)
        XCTAssertEqual(installer.statusText, "OpenClaw 已安装")
        XCTAssertEqual(installer.detailText, "status 已返回最近状态。")
        XCTAssertEqual(installer.statusExcerpt, "plugins.allow is empty; discovered non-bundled plugins.")
        XCTAssertEqual(installer.installedBinaryPath, "/opt/homebrew/bin/openclaw")
        XCTAssertNotNil(installer.lastStatusRefreshDate)
    }

    func testMergeStatusSnapshotSurfacesMissingGatewayService() {
        let openClawSnapshot = OpenClawStatusSnapshot(
            title: "OpenClaw 已安装",
            detail: "status 已返回最近状态。",
            excerpt: "status ok",
            binaryPath: "/opt/homebrew/bin/openclaw"
        )
        let gatewaySnapshot = OpenClawGatewayStatusSnapshot(
            state: .missing,
            detail: "Gateway 服务尚未安装到 launchd。",
            binaryPath: "/opt/homebrew/bin/openclaw",
            runtimeStatus: "unknown",
            serviceLoaded: false,
            serviceLabel: "LaunchAgent",
            pid: nil,
            missingUnit: true
        )

        let merged = OpenClawInstaller.mergeStatusSnapshot(openClawSnapshot, gatewaySnapshot: gatewaySnapshot)

        XCTAssertEqual(merged.title, "OpenClaw 已安装")
        XCTAssertEqual(merged.detail, "OpenClaw CLI 已安装，但 Gateway 服务尚未安装到 launchd。")
        XCTAssertEqual(merged.excerpt, "status ok")
    }

    func testPrepareGatewayServiceReturnsReadyWhenInstallRegistersLaunchAgent() {
        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { "generated-token" },
            runGatewayCommand: { command, _, _ in
                XCTAssertEqual(command, OpenClawInstaller.gatewayInstallCommand)
                return OpenClawGatewayCommandResult(
                    output: #"{"ok":true,"message":"Gateway service installed."}"#,
                    exitStatus: 0,
                    timedOut: false
                )
            },
            fetchGatewayStatus: { _, _ in
                OpenClawGatewayStatusSnapshot(
                    state: .stopped,
                    detail: "service not loaded",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    runtimeStatus: nil,
                    serviceLoaded: false,
                    serviceLabel: "LaunchAgent",
                    pid: nil,
                    missingUnit: false
                )
            }
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.token, "generated-token")
        XCTAssertNil(result.failureDetail)
    }

    func testPrepareGatewayServiceFailsWhenGatewayInstallLeavesMissingUnit() {
        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { "generated-token" },
            runGatewayCommand: { _, _, _ in
                OpenClawGatewayCommandResult(
                    output: #"{"ok":true,"message":"Gateway service installed."}"#,
                    exitStatus: 0,
                    timedOut: false
                )
            },
            fetchGatewayStatus: { _, _ in
                OpenClawGatewayStatusSnapshot(
                    state: .missing,
                    detail: "Bad request. Could not find service ai.openclaw.gateway",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    runtimeStatus: "unknown",
                    serviceLoaded: false,
                    serviceLabel: "LaunchAgent",
                    pid: nil,
                    missingUnit: true
                )
            }
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.failureDetail, "Gateway 服务安装命令已完成，但 launchd 中仍未注册 ai.openclaw.gateway。")
    }

    func testPrepareGatewayServiceFailsWhenTokenConfigurationFails() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "token write failed" }
        }

        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { throw TestError() }
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.failureDetail, "Gateway token 初始化失败：token write failed")
    }

    func testRefreshInstallationStatusUsesMissingOverride() {
        let installer = OpenClawInstaller(
            overrideState: OpenClawInstallerOverride(state: .missing),
            autoStartTimer: false
        )

        installer.refreshInstallationStatus()

        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.installedBinaryPath)
        XCTAssertEqual(installer.statusText, "准备安装 OpenClaw。")
        XCTAssertEqual(installer.detailText, "点击按钮后会执行官方安装脚本，但不会进入 onboarding。")
    }

    func testSharedInstallerStartsWithUserFacingIdleMessages() {
        let installer = OpenClawInstaller(autoStartTimer: false)

        XCTAssertFalse(installer.isInstalling)
        XCTAssertFalse(installer.isUninstalling)
        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.lastStatusRefreshDate)
        XCTAssertEqual(installer.statusText, "准备安装 OpenClaw。")
        XCTAssertEqual(installer.detailText, "点击按钮后会执行官方安装脚本，但不会进入 onboarding。")
    }
}
