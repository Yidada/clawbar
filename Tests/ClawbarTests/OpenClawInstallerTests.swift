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

    func testSharedInstallerStartsWithUserFacingIdleMessages() {
        let installer = OpenClawInstaller(autoStartTimer: false)

        XCTAssertFalse(installer.isInstalling)
        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.lastStatusRefreshDate)
        XCTAssertEqual(installer.statusText, "准备安装 OpenClaw。")
        XCTAssertEqual(installer.detailText, "点击按钮后会执行官方安装脚本，但不会进入 onboarding。")
    }
}
