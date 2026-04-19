import Foundation

enum AgentRuntimeID: String, Equatable, Sendable, CaseIterable, Identifiable {
    case openClaw = "openclaw"
    case hermes

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openClaw:
            "OpenClaw"
        case .hermes:
            "Hermes"
        }
    }
}

@MainActor
protocol AgentRuntime: AnyObject {
    var identifier: AgentRuntimeID { get }
    var displayName: String { get }
    var healthSnapshot: AgentHealthSnapshot? { get }
    func refresh(force: Bool) async
}

@MainActor
protocol AgentInstallable: AgentRuntime {
    var isInstalled: Bool { get }
    var isBusy: Bool { get }
    func install() async
    func uninstall() async
}

@MainActor
protocol AgentProviderCapable: AgentRuntime {
    var supportedProviders: [ProviderKind] { get }
}

@MainActor
protocol AgentChannelCapable: AgentRuntime {}

@MainActor
protocol AgentMessagingGatewayCapable: AgentRuntime {}

@MainActor
protocol AgentTUILaunchable: AgentRuntime {
    func launchTUI()
}

@MainActor
final class AgentRuntimeRegistry {
    static let shared = AgentRuntimeRegistry()

    private(set) var runtimes: [AgentRuntime]

    init(runtimes: [AgentRuntime]? = nil) {
        self.runtimes = runtimes ?? AgentRuntimeRegistry.makeDefaultRuntimes()
    }

    func runtime(for identifier: AgentRuntimeID) -> AgentRuntime? {
        runtimes.first { $0.identifier == identifier }
    }

    private static func makeDefaultRuntimes() -> [AgentRuntime] {
        [
            OpenClawRuntime.shared,
            HermesRuntime.shared,
        ]
    }
}
