public enum MenuContentElement: String, Equatable, Sendable {
    case title
    case subtitle
    case installButton
    case openClawSection
    case openClawTitle
    case openClawBinaryPath
    case openClawDetail
    case openClawExcerpt
    case quitButton
}

public struct MenuContentModel: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let installButtonTitle: String
    public let quitButtonTitle: String
    public let width: Double

    public init(
        title: String,
        subtitle: String,
        installButtonTitle: String,
        quitButtonTitle: String,
        width: Double
    ) {
        self.title = title
        self.subtitle = subtitle
        self.installButtonTitle = installButtonTitle
        self.quitButtonTitle = quitButtonTitle
        self.width = width
    }

    public static func makeDefault(configuration: AppConfiguration = .makeDefault()) -> Self {
        Self(
            title: configuration.helloTitle,
            subtitle: configuration.helloSubtitle,
            installButtonTitle: configuration.installLabel,
            quitButtonTitle: configuration.quitLabel,
            width: configuration.menuWidth
        )
    }

    public func accessibilityIdentifier(for element: MenuContentElement) -> String {
        "clawbar.menu.\(element.rawValue)"
    }
}
