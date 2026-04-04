public struct AppConfiguration: Equatable, Sendable {
    public let appName: String
    public let menuBarTitle: String
    public let systemImageName: String
    public let helloTitle: String
    public let helloSubtitle: String
    public let installLabel: String
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
        systemImageName: String,
        helloTitle: String,
        helloSubtitle: String,
        installLabel: String,
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
        self.systemImageName = systemImageName
        self.helloTitle = helloTitle
        self.helloSubtitle = helloSubtitle
        self.installLabel = installLabel
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
            systemImageName: "hand.wave.fill",
            helloTitle: "Hello World",
            helloSubtitle: "This is the smallest possible Clawbar scaffold.",
            installLabel: "安装 OpenClaw",
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
            menuWidth: 320
        )
    }

    public func isSmokeTestEnabled(in environment: [String: String]) -> Bool {
        environment[smokeTestEnvironmentVariable] == "1"
    }
}
