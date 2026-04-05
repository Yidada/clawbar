import XCTest
@testable import Clawbar
@testable import ClawbarKit

final class MenuPanelSnapshotTests: XCTestCase {
    func testInstalledSnapshotShowsSummaryRowsAndActions() {
        let snapshot = MenuPanelSnapshotFactory.make(
            model: .makeDefault(),
            isInstalled: true,
            isBusy: false,
            isRefreshingStatus: false,
            lastStatusRefreshDate: Date(timeIntervalSince1970: 123),
            statusText: "OpenClaw 已安装",
            detailText: "Provider 已配置 · Gateway 可达 · Channel 已就绪",
            installedBinaryPath: "/opt/homebrew/bin/openclaw",
            statusExcerpt: "OpenClaw 2026.4.2",
            healthSnapshot: .deterministicInstalled
        )

        XCTAssertEqual(snapshot.state, .installed)
        XCTAssertEqual(snapshot.title, "OpenClaw")
        XCTAssertEqual(snapshot.subtitle, "Provider 已配置 · Gateway 可达 · Channel 已就绪")
        XCTAssertEqual(snapshot.metadata, "OpenClaw 2026.4.2")
        XCTAssertEqual(snapshot.binaryPath, "/opt/homebrew/bin/openclaw")
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertNil(snapshot.rows[0].detail)
        XCTAssertTrue(snapshot.showsTUIDebugAction)
        XCTAssertTrue(snapshot.showsSettingsAction)
        XCTAssertTrue(snapshot.showsUninstallAction)
        XCTAssertFalse(snapshot.showsInstallAction)
    }

    func testMissingSnapshotShowsInstallActionAndFriendlySubtitle() {
        let snapshot = MenuPanelSnapshotFactory.make(
            model: .makeDefault(),
            isInstalled: false,
            isBusy: false,
            isRefreshingStatus: false,
            lastStatusRefreshDate: Date(timeIntervalSince1970: 123),
            statusText: "准备安装 OpenClaw。",
            detailText: "点击按钮后会执行官方安装脚本，但不会进入 onboarding。",
            installedBinaryPath: nil,
            statusExcerpt: nil,
            healthSnapshot: nil
        )

        XCTAssertEqual(snapshot.state, .missing)
        XCTAssertEqual(snapshot.title, "OpenClaw 未安装")
        XCTAssertEqual(snapshot.subtitle, "安装后即可在此查看 Provider、Gateway 和 Channel 摘要。")
        XCTAssertNil(snapshot.metadata)
        XCTAssertTrue(snapshot.showsInstallAction)
        XCTAssertFalse(snapshot.showsTUIDebugAction)
        XCTAssertFalse(snapshot.showsUninstallAction)
        XCTAssertEqual(snapshot.rows, [])
    }

    func testInitialLoadingSnapshotShowsNeutralHeaderAndNoInstallAction() {
        let snapshot = MenuPanelSnapshotFactory.make(
            model: .makeDefault(),
            isInstalled: false,
            isBusy: false,
            isRefreshingStatus: true,
            lastStatusRefreshDate: nil,
            statusText: "准备安装 OpenClaw。",
            detailText: "点击按钮后会执行官方安装脚本，但不会进入 onboarding。",
            installedBinaryPath: nil,
            statusExcerpt: nil,
            healthSnapshot: nil
        )

        XCTAssertEqual(snapshot.state, .loading)
        XCTAssertEqual(snapshot.title, "OpenClaw")
        XCTAssertEqual(snapshot.subtitle, "正在读取本机状态…")
        XCTAssertNil(snapshot.metadata)
        XCTAssertFalse(snapshot.showsInstallAction)
        XCTAssertFalse(snapshot.showsTUIDebugAction)
        XCTAssertFalse(snapshot.showsUninstallAction)
        XCTAssertTrue(snapshot.showsSettingsAction)
        XCTAssertTrue(snapshot.showsQuitAction)
        XCTAssertEqual(snapshot.rows, [])
    }

    func testWarningSnapshotKeepsProblemDetailVisible() {
        let warningSnapshot = OpenClawHealthSnapshot(
            runtimeVersion: "2026.4.2",
            dimensions: [
                OpenClawHealthDimensionSnapshot(
                    dimension: .provider,
                    level: .healthy,
                    statusLabel: "已配置",
                    summary: "OpenRouter / qwen/qwen3.6-plus:free",
                    detail: "认证来源：env: OPENROUTER_API_KEY"
                ),
                OpenClawHealthDimensionSnapshot(
                    dimension: .gateway,
                    level: .warning,
                    statusLabel: "不可达",
                    summary: "后台服务运行中，但控制面不可达",
                    detail: "Gateway 后台服务运行中，但当前探活失败。"
                ),
                OpenClawHealthDimensionSnapshot(
                    dimension: .channel,
                    level: .healthy,
                    statusLabel: "已就绪",
                    summary: "openclaw-weixin / 已配置",
                    detail: "openclaw-weixin: 已配置"
                ),
            ]
        )

        let snapshot = MenuPanelSnapshotFactory.make(
            model: .makeDefault(),
            isInstalled: true,
            isBusy: false,
            isRefreshingStatus: false,
            lastStatusRefreshDate: Date(timeIntervalSince1970: 123),
            statusText: "OpenClaw 已安装",
            detailText: "Provider 已配置 · Gateway 不可达 · Channel 已就绪",
            installedBinaryPath: "/opt/homebrew/bin/openclaw",
            statusExcerpt: "OpenClaw 2026.4.2",
            healthSnapshot: warningSnapshot
        )

        XCTAssertEqual(snapshot.rows[1].statusLabel, "不可达")
        XCTAssertEqual(snapshot.rows[1].detail, "Gateway 后台服务运行中，但当前探活失败。")
    }
}
