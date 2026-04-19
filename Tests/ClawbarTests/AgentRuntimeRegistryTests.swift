import XCTest
@testable import Clawbar

@MainActor
final class AgentRuntimeRegistryTests: XCTestCase {
    func testDefaultRegistryListsOpenClawAndHermesInOrder() {
        let registry = AgentRuntimeRegistry()

        XCTAssertEqual(registry.runtimes.map(\.identifier), [.openClaw, .hermes])
    }

    func testLookupReturnsRuntimeForKnownIdentifier() {
        let registry = AgentRuntimeRegistry()

        XCTAssertTrue(registry.runtime(for: .openClaw) is OpenClawRuntime)
        XCTAssertTrue(registry.runtime(for: .hermes) is HermesRuntime)
    }

    func testOpenClawRuntimeAdvertisesAllExpectedCapabilities() {
        let runtime: AgentRuntime = OpenClawRuntime.shared

        XCTAssertTrue(runtime is AgentInstallable)
        XCTAssertTrue(runtime is AgentProviderCapable)
        XCTAssertTrue(runtime is AgentChannelCapable)
        XCTAssertTrue(runtime is AgentMessagingGatewayCapable)
        XCTAssertTrue(runtime is AgentTUILaunchable)
    }

    func testHermesRuntimeAdvertisesAllExpectedCapabilities() {
        let runtime: AgentRuntime = HermesRuntime.shared

        XCTAssertEqual(runtime.identifier, .hermes)
        XCTAssertEqual(runtime.displayName, "Hermes")
        XCTAssertTrue(runtime is AgentInstallable)
        XCTAssertTrue(runtime is AgentProviderCapable)
        XCTAssertTrue(runtime is AgentMessagingGatewayCapable)
        XCTAssertTrue(runtime is AgentTUILaunchable)
        // Hermes does not implement AgentChannelCapable — channel platforms go through Gateway.
        XCTAssertFalse(runtime is AgentChannelCapable)
    }

    func testHermesRuntimeExposesSupportedProvidersWithoutOpenClawSpecificEntries() {
        let runtime = HermesRuntime.shared
        let supported = runtime.supportedProviders

        XCTAssertTrue(supported.contains(.openAI))
        XCTAssertTrue(supported.contains(.anthropic))
        XCTAssertTrue(supported.contains(.openRouter))
        XCTAssertTrue(supported.contains(.ollama))
        XCTAssertTrue(supported.contains(.custom))
        XCTAssertFalse(supported.contains(.openAICodex))
    }
}
