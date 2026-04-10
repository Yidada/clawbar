import XCTest
@testable import Clawbar

final class OpenClawProviderManagerTests: XCTestCase {
    func testParseStatusSnapshotReadsDefaultModelAndAuthSources() {
        let output = """
        shell warning
        {
          "configPath": "/Users/test/.openclaw/openclaw.json",
          "defaultModel": "ollama/gemma4",
          "auth": {
            "providers": [
              {
                "provider": "ollama",
                "effective": {
                  "kind": "env",
                  "detail": "OLLAMA_API_KEY"
                },
                "env": {
                  "value": "ollama-local",
                  "source": "env: OLLAMA_API_KEY"
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
        XCTAssertEqual(snapshot?.defaultModelRef, "ollama/gemma4")
        XCTAssertEqual(snapshot?.authStates["ollama"]?.kind, "env")
        XCTAssertEqual(snapshot?.authStates["ollama"]?.source, "env: OLLAMA_API_KEY")
    }

    func testMakeSavePlanUsesFixedOllamaGemma4Flow() {
        let plan = OpenClawProviderManager.makeSavePlan()

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
            "--custom-model-id", "gemma4",
        ])
        XCTAssertEqual(plan[1].arguments, [
            "config",
            "set",
            "agents.defaults.model.primary",
            "ollama/gemma4",
        ])
    }

    func testMakeSavePlanAppendsLegacyProviderCleanup() {
        let plan = OpenClawProviderManager.makeSavePlan(
            existingLegacyProviderPaths: [
                "models.providers.openai",
                "models.providers.custom",
            ]
        )

        XCTAssertEqual(plan.count, 4)
        XCTAssertEqual(plan[2].arguments, ["config", "unset", "models.providers.openai"])
        XCTAssertEqual(plan[3].arguments, ["config", "unset", "models.providers.custom"])
    }

    func testRenderCommandLineUsesOpenClawPrefix() {
        let invocation = OpenClawProviderCLIInvocation(
            arguments: ["config", "set", "agents.defaults.model.primary", "ollama/gemma4"],
            redactedArguments: ["config", "set", "agents.defaults.model.primary", "ollama/gemma4"]
        )

        XCTAssertEqual(
            OpenClawProviderManager.renderCommandLine(invocation),
            "$ openclaw config set agents.defaults.model.primary ollama/gemma4"
        )
    }
}
