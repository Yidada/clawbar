public enum MenuContentElement: String, Equatable, Sendable {
    case headerTitle
    case headerSubtitle
    case headerMetadata
    case binaryPath
    case providerRow
    case gatewayRow
    case channelRow
    case installButton
    case upgradeButton
    case uninstallButton
    case tuiDebugButton
    case managementButton
    case quitButton
}

public struct MenuContentModel: Equatable, Sendable {
    public let installedTitle: String
    public let loadingSubtitle: String
    public let missingTitle: String
    public let missingSubtitle: String
    public let refreshingStatusLabel: String
    public let installButtonTitle: String
    public let upgradeButtonTitle: String
    public let uninstallButtonTitle: String
    public let tuiDebugButtonTitle: String
    public let managementButtonTitle: String
    public let quitButtonTitle: String
    public let width: Double

    public init(
        installedTitle: String,
        loadingSubtitle: String,
        missingTitle: String,
        missingSubtitle: String,
        refreshingStatusLabel: String,
        installButtonTitle: String,
        upgradeButtonTitle: String,
        uninstallButtonTitle: String,
        tuiDebugButtonTitle: String,
        managementButtonTitle: String,
        quitButtonTitle: String,
        width: Double
    ) {
        self.installedTitle = installedTitle
        self.loadingSubtitle = loadingSubtitle
        self.missingTitle = missingTitle
        self.missingSubtitle = missingSubtitle
        self.refreshingStatusLabel = refreshingStatusLabel
        self.installButtonTitle = installButtonTitle
        self.upgradeButtonTitle = upgradeButtonTitle
        self.uninstallButtonTitle = uninstallButtonTitle
        self.tuiDebugButtonTitle = tuiDebugButtonTitle
        self.managementButtonTitle = managementButtonTitle
        self.quitButtonTitle = quitButtonTitle
        self.width = width
    }

    public static func makeDefault(configuration: AppConfiguration = .makeDefault()) -> Self {
        Self(
            installedTitle: configuration.menuInstalledTitle,
            loadingSubtitle: configuration.menuLoadingSubtitle,
            missingTitle: configuration.menuMissingTitle,
            missingSubtitle: configuration.menuMissingSubtitle,
            refreshingStatusLabel: configuration.menuRefreshingStatusLabel,
            installButtonTitle: configuration.installLabel,
            upgradeButtonTitle: configuration.upgradeLabel,
            uninstallButtonTitle: configuration.uninstallLabel,
            tuiDebugButtonTitle: configuration.tuiDebugLabel,
            managementButtonTitle: configuration.applicationLabel,
            quitButtonTitle: configuration.quitLabel,
            width: configuration.menuWidth
        )
    }

    public func accessibilityIdentifier(for element: MenuContentElement) -> String {
        "clawbar.menu.\(element.rawValue)"
    }
}
