import XCTest
@testable import Clawbar

final class OpenClawProviderManagerTests: XCTestCase {
    func testParseStatusSnapshotReadsDefaultModelAndAuthSources() {
        let output = """
        shell warning
        {
          "configPath": "/Users/test/.openclaw/openclaw.json",
          "defaultModel": "openrouter/anthropic/claude-sonnet-4-6",
          "auth": {
            "providers": [
              {
                "provider": "openrouter",
                "effective": {
                  "kind": "env",
                  "detail": "sk-or-v1...1234"
                },
                "env": {
                  "value": "sk-or-v1...1234",
                  "source": "env: OPENROUTER_API_KEY"
                }
              },
              {
                "provider": "anthropic",
                "effective": {
                  "kind": "missing",
                  "detail": "missing"
                }
              }
            ]
          }
        }
        """

        let snapshot = OpenClawProviderManager.parseStatusSnapshot(
            output,
            binaryPath: "/opt/homebrew/bin/openclaw"
        )

        XCTAssertEqual(snapshot?.configPath, "/Users/test/.openclaw/openclaw.json")
        XCTAssertEqual(snapshot?.defaultModelRef, "openrouter/anthropic/claude-sonnet-4-6")
        XCTAssertEqual(snapshot?.authStates["openrouter"]?.kind, "env")
        XCTAssertEqual(snapshot?.authStates["openrouter"]?.source, "env: OPENROUTER_API_KEY")
        XCTAssertEqual(snapshot?.authStates["anthropic"]?.isConfigured, false)
    }

    func testMakeSavePlanUsesCustomOnboardForCustomProvider() throws {
        let plan = try OpenClawProviderManager.makeSavePlan(
            provider: .custom,
            customCompatibility: .anthropic,
            baseURL: "https://llm.example.com/v1",
            model: "foo-large",
            apiKey: "secret-key"
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].arguments, [
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-daemon",
            "--skip-channels",
            "--skip-skills",
            "--skip-search",
            "--skip-health",
            "--skip-ui",
            "--auth-choice", "custom-api-key",
            "--custom-provider-id", "custom",
            "--custom-base-url", "https://llm.example.com/v1",
            "--custom-model-id", "foo-large",
            "--custom-compatibility", "anthropic",
            "--custom-api-key", "secret-key",
        ])
        XCTAssertEqual(plan[0].redactedArguments.suffix(2), ["--custom-api-key", "<redacted>"])
        XCTAssertEqual(plan[1].arguments, [
            "config",
            "set",
            "agents.defaults.model.primary",
            "custom/foo-large",
        ])
    }

    func testMakeSavePlanUsesProviderSpecificOnboardForOpenAIWithoutCustomBaseURL() throws {
        let plan = try OpenClawProviderManager.makeSavePlan(
            provider: .openAI,
            customCompatibility: .openAI,
            baseURL: "",
            model: "gpt-5.4",
            apiKey: "sk-test"
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].arguments, [
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-daemon",
            "--skip-channels",
            "--skip-skills",
            "--skip-search",
            "--skip-health",
            "--skip-ui",
            "--auth-choice", "openai-api-key",
            "--openai-api-key", "sk-test",
        ])
        XCTAssertEqual(plan[1].arguments.last, "openai/gpt-5.4")
    }

    func testMakeSavePlanUsesOllamaOnboardAndSuggestedBaseURL() throws {
        let plan = try OpenClawProviderManager.makeSavePlan(
            provider: .ollama,
            customCompatibility: .openAI,
            baseURL: "",
            model: "",
            apiKey: ""
        )

        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan[0].arguments, [
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-daemon",
            "--skip-channels",
            "--skip-skills",
            "--skip-search",
            "--skip-health",
            "--skip-ui",
            "--auth-choice", "ollama",
            "--custom-base-url", "http://127.0.0.1:11434",
            "--custom-model-id", "glm-4.7-flash",
        ])
        XCTAssertEqual(plan[1].arguments.last, "ollama/glm-4.7-flash")
    }

    func testMakeSavePlanRejectsCustomProviderWithoutBaseURL() {
        XCTAssertThrowsError(
            try OpenClawProviderManager.makeSavePlan(
                provider: .custom,
                customCompatibility: .openAI,
                baseURL: "",
                model: "foo",
                apiKey: ""
            )
        ) { error in
            XCTAssertEqual(error as? OpenClawProviderSavePlanError, .missingCustomBaseURL)
        }
    }
}
