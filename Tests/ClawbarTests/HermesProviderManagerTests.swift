import XCTest
@testable import Clawbar

final class HermesProviderManagerTests: XCTestCase {
    func testMakeSavePlanRejectsUnsupportedProviders() {
        XCTAssertThrowsError(try HermesProviderManager.makeSavePlan(
            provider: .openAICodex,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-4o",
            apiKey: ""
        )) { error in
            XCTAssertEqual(error as? HermesProviderSavePlanError, .unsupportedProvider(.openAICodex))
        }

        XCTAssertThrowsError(try HermesProviderManager.makeSavePlan(
            provider: .liteLLM,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-4o",
            apiKey: ""
        )) { error in
            XCTAssertEqual(error as? HermesProviderSavePlanError, .unsupportedProvider(.liteLLM))
        }
    }

    func testMakeSavePlanRequiresModel() {
        XCTAssertThrowsError(try HermesProviderManager.makeSavePlan(
            provider: .openAI,
            customCompatibility: .openAI,
            baseURL: "",
            model: "  ",
            apiKey: "sk-foo"
        )) { error in
            XCTAssertEqual(error as? HermesProviderSavePlanError, .missingModel)
        }
    }

    func testOpenAISavePlanIncludesModelProviderAndAPIKey() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .openAI,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-4o",
            apiKey: "sk-secret"
        )

        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan[0].arguments, ["config", "set", "model", "gpt-4o"])
        XCTAssertEqual(plan[1].arguments, ["config", "set", "provider", "openai"])
        XCTAssertEqual(plan[2].arguments, ["config", "set", "OPENAI_API_KEY", "sk-secret"])
        XCTAssertEqual(plan[2].redactedArguments, ["config", "set", "OPENAI_API_KEY", "<redacted>"])
    }

    func testOpenAISavePlanIncludesBaseURLWhenProvided() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .openAI,
            customCompatibility: .openAI,
            baseURL: "https://proxy.example.com/v1",
            model: "gpt-4o",
            apiKey: "sk-secret"
        )

        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan[3].arguments, ["config", "set", "OPENAI_BASE_URL", "https://proxy.example.com/v1"])
    }

    func testAnthropicSavePlanRedactsAPIKey() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .anthropic,
            customCompatibility: .openAI,
            baseURL: "",
            model: "claude-opus-4.6",
            apiKey: "sk-ant-secret"
        )

        XCTAssertEqual(plan.map(\.arguments), [
            ["config", "set", "model", "claude-opus-4.6"],
            ["config", "set", "provider", "anthropic"],
            ["config", "set", "ANTHROPIC_API_KEY", "sk-ant-secret"],
        ])
        XCTAssertEqual(plan.last?.redactedArguments, ["config", "set", "ANTHROPIC_API_KEY", "<redacted>"])
    }

    func testOpenRouterSavePlanRoutesToOpenRouterEnvKeys() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .openRouter,
            customCompatibility: .openAI,
            baseURL: "",
            model: "anthropic/claude-opus-4.6",
            apiKey: "sk-or-v1-secret"
        )

        XCTAssertEqual(plan.map(\.arguments), [
            ["config", "set", "model", "anthropic/claude-opus-4.6"],
            ["config", "set", "provider", "openrouter"],
            ["config", "set", "OPENROUTER_API_KEY", "sk-or-v1-secret"],
        ])
    }

    func testOllamaSavePlanRequiresBaseURL() {
        XCTAssertThrowsError(try HermesProviderManager.makeSavePlan(
            provider: .ollama,
            customCompatibility: .openAI,
            baseURL: "",
            model: "llama3.1",
            apiKey: ""
        )) { error in
            XCTAssertEqual(error as? HermesProviderSavePlanError, .missingOllamaBaseURL)
        }
    }

    func testOllamaSavePlanIncludesBaseURL() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .ollama,
            customCompatibility: .openAI,
            baseURL: "http://localhost:11434",
            model: "llama3.1",
            apiKey: ""
        )

        XCTAssertEqual(plan.map(\.arguments), [
            ["config", "set", "model", "llama3.1"],
            ["config", "set", "provider", "ollama"],
            ["config", "set", "OLLAMA_BASE_URL", "http://localhost:11434"],
        ])
    }

    func testCustomSavePlanRequiresBaseURL() {
        XCTAssertThrowsError(try HermesProviderManager.makeSavePlan(
            provider: .custom,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-4o",
            apiKey: "sk-foo"
        )) { error in
            XCTAssertEqual(error as? HermesProviderSavePlanError, .missingCustomBaseURL)
        }
    }

    func testCustomSavePlanWithOpenAICompatibilityWritesOpenAIPrefixedKeys() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .custom,
            customCompatibility: .openAI,
            baseURL: "https://proxy.example.com/v1",
            model: "gpt-4o-mini",
            apiKey: "sk-secret"
        )

        XCTAssertEqual(plan.map(\.arguments), [
            ["config", "set", "model", "gpt-4o-mini"],
            ["config", "set", "provider", "openai"],
            ["config", "set", "OPENAI_BASE_URL", "https://proxy.example.com/v1"],
            ["config", "set", "OPENAI_API_KEY", "sk-secret"],
        ])
    }

    func testCustomSavePlanWithAnthropicCompatibilityWritesAnthropicPrefixedKeys() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .custom,
            customCompatibility: .anthropic,
            baseURL: "https://proxy.example.com/v1",
            model: "claude-haiku",
            apiKey: "sk-secret"
        )

        XCTAssertEqual(plan.map(\.arguments), [
            ["config", "set", "model", "claude-haiku"],
            ["config", "set", "provider", "anthropic"],
            ["config", "set", "ANTHROPIC_BASE_URL", "https://proxy.example.com/v1"],
            ["config", "set", "ANTHROPIC_API_KEY", "sk-secret"],
        ])
    }

    func testSavePlanOmitsAPIKeyWhenNotProvided() throws {
        let plan = try HermesProviderManager.makeSavePlan(
            provider: .openAI,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-4o",
            apiKey: ""
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertFalse(plan.contains { $0.arguments.contains("OPENAI_API_KEY") })
    }
}
