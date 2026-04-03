public enum AppActivationPolicy: String, Equatable, Sendable {
    case accessory
    case regular
}

public struct ApplicationLaunchPlan: Equatable, Sendable {
    public let activationPolicy: AppActivationPolicy
    public let activatesApp: Bool
    public let showsSmokeTestWindow: Bool

    public init(
        activationPolicy: AppActivationPolicy,
        activatesApp: Bool,
        showsSmokeTestWindow: Bool
    ) {
        self.activationPolicy = activationPolicy
        self.activatesApp = activatesApp
        self.showsSmokeTestWindow = showsSmokeTestWindow
    }
}

public enum AppMode: String, Equatable, Sendable {
    case menuBar
    case smokeTest
    case uiTest

    public static func detect(
        in environment: [String: String],
        configuration: AppConfiguration = .makeDefault()
    ) -> Self {
        if environment["CLAWBAR_UI_TEST"] == "1" {
            return .uiTest
        }

        return configuration.isSmokeTestEnabled(in: environment) ? .smokeTest : .menuBar
    }

    public var activationPolicy: AppActivationPolicy {
        switch self {
        case .menuBar:
            .accessory
        case .smokeTest, .uiTest:
            .regular
        }
    }

    public var showsSmokeTestWindow: Bool {
        self == .smokeTest
    }

    public var shouldActivateOnLaunch: Bool {
        switch self {
        case .menuBar:
            false
        case .smokeTest, .uiTest:
            true
        }
    }
}

public struct AppLifecycleController: Sendable {
    public let configuration: AppConfiguration

    public init(configuration: AppConfiguration = .makeDefault()) {
        self.configuration = configuration
    }

    public func mode(in environment: [String: String]) -> AppMode {
        AppMode.detect(in: environment, configuration: configuration)
    }

    public func launchPlan(in environment: [String: String]) -> ApplicationLaunchPlan {
        let currentMode = mode(in: environment)
        return ApplicationLaunchPlan(
            activationPolicy: currentMode.activationPolicy,
            activatesApp: currentMode.shouldActivateOnLaunch,
            showsSmokeTestWindow: currentMode.showsSmokeTestWindow
        )
    }
}
