public struct AppConfiguration: Equatable, Sendable {
    public let appName: String
    public let menuBarTitle: String
    public let systemImageName: String
    public let helloTitle: String
    public let helloSubtitle: String
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
            quitLabel: "Quit",
            smokeTestEnvironmentVariable: "CLAWBAR_SMOKE_TEST",
            smokeTestWindowTitle: "Clawbar Smoke Test",
            menuWidth: 260
        )
    }

    public func isSmokeTestEnabled(in environment: [String: String]) -> Bool {
        environment[smokeTestEnvironmentVariable] == "1"
    }
}
