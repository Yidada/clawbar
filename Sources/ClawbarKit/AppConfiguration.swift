public struct AppConfiguration: Equatable, Sendable {
    public let appName: String
    public let menuBarTitle: String
    public let menuInstalledTitle: String
    public let menuLoadingSubtitle: String
    public let menuMissingTitle: String
    public let menuMissingSubtitle: String
    public let menuRefreshingStatusLabel: String
    public let installLabel: String
    public let upgradeLabel: String
    public let uninstallLabel: String
    public let tuiDebugLabel: String
    public let applicationLabel: String
    public let applicationWindowTitle: String
    public let providerLabel: String
    public let providerWindowTitle: String
    public let gatewayLabel: String
    public let gatewayWindowTitle: String
    public let channelsLabel: String
    public let channelsWindowTitle: String
    public let quitLabel: String
    public let smokeTestEnvironmentVariable: String
    public let smokeTestWindowTitle: String
    public let menuWidth: Double

    public init(
        appName: String,
        menuBarTitle: String,
        menuInstalledTitle: String,
        menuLoadingSubtitle: String,
        menuMissingTitle: String,
        menuMissingSubtitle: String,
        menuRefreshingStatusLabel: String,
        installLabel: String,
        upgradeLabel: String,
        uninstallLabel: String,
        tuiDebugLabel: String,
        applicationLabel: String,
        applicationWindowTitle: String,
        providerLabel: String,
        providerWindowTitle: String,
        gatewayLabel: String,
        gatewayWindowTitle: String,
        channelsLabel: String,
        channelsWindowTitle: String,
        quitLabel: String,
        smokeTestEnvironmentVariable: String,
        smokeTestWindowTitle: String,
        menuWidth: Double
    ) {
        self.appName = appName
        self.menuBarTitle = menuBarTitle
        self.menuInstalledTitle = menuInstalledTitle
        self.menuLoadingSubtitle = menuLoadingSubtitle
        self.menuMissingTitle = menuMissingTitle
        self.menuMissingSubtitle = menuMissingSubtitle
        self.menuRefreshingStatusLabel = menuRefreshingStatusLabel
        self.installLabel = installLabel
        self.upgradeLabel = upgradeLabel
        self.uninstallLabel = uninstallLabel
        self.tuiDebugLabel = tuiDebugLabel
        self.applicationLabel = applicationLabel
        self.applicationWindowTitle = applicationWindowTitle
        self.providerLabel = providerLabel
        self.providerWindowTitle = providerWindowTitle
        self.gatewayLabel = gatewayLabel
        self.gatewayWindowTitle = gatewayWindowTitle
        self.channelsLabel = channelsLabel
        self.channelsWindowTitle = channelsWindowTitle
        self.quitLabel = quitLabel
        self.smokeTestEnvironmentVariable = smokeTestEnvironmentVariable
        self.smokeTestWindowTitle = smokeTestWindowTitle
        self.menuWidth = menuWidth
    }

    public static func makeDefault() -> Self {
        Self(
            appName: "Clawbar",
            menuBarTitle: "Clawbar",
            menuInstalledTitle: "OpenClaw",
            menuLoadingSubtitle: "正在读取本机状态…",
            menuMissingTitle: "OpenClaw 未安装",
            menuMissingSubtitle: "安装后即可在此查看 Provider、Gateway 和 Channel 摘要。",
            menuRefreshingStatusLabel: "正在刷新状态…",
            installLabel: "安装 OpenClaw",
            upgradeLabel: "升级 OpenClaw",
            uninstallLabel: "卸载 OpenClaw",
            tuiDebugLabel: "启动 TUI",
            applicationLabel: "Settings",
            applicationWindowTitle: "Settings",
            providerLabel: "管理 Provider",
            providerWindowTitle: "Provider 管理",
            gatewayLabel: "管理 Gateway",
            gatewayWindowTitle: "Gateway 管理",
            channelsLabel: "管理 Channels",
            channelsWindowTitle: "Channels 管理",
            quitLabel: "Quit",
            smokeTestEnvironmentVariable: "CLAWBAR_SMOKE_TEST",
            smokeTestWindowTitle: "Clawbar Smoke Test",
            menuWidth: 360
        )
    }

    public func isSmokeTestEnabled(in environment: [String: String]) -> Bool {
        environment[smokeTestEnvironmentVariable] == "1"
    }
}
