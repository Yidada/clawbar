import XCTest
@testable import Clawbar

final class ProviderManagementDisplayStateTests: XCTestCase {
    func testCurrentStatusContentShowsConnectedOpenAICodexState() {
        let content = ProviderCurrentStatusPresenter.make(
            currentProvider: .openAICodex,
            currentModel: "gpt-5.4",
            currentAuthState: OpenClawProviderAuthState(
                kind: "oauth",
                detail: "oauth (openai-codex:user@example.com)",
                source: nil
            ),
            selectedProvider: .openAICodex,
            isInteractiveLoginInProgress: false,
            hasPendingCredentialInput: false
        )

        XCTAssertEqual(content.title, "OpenAI Codex 已连接")
        XCTAssertEqual(content.detail, "当前默认模型是 gpt-5.4。")
        XCTAssertEqual(content.connectionLabel, "已连接")
        XCTAssertEqual(content.nextStep, "如需切换 Provider 或模型，在下方修改后保存。")
    }

    func testCurrentStatusContentShowsNeedsLoginForOpenAICodexWithoutOAuth() {
        let content = ProviderCurrentStatusPresenter.make(
            currentProvider: .openAICodex,
            currentModel: "gpt-5.4",
            currentAuthState: OpenClawProviderAuthState(
                kind: "missing",
                detail: "missing",
                source: nil
            ),
            selectedProvider: .openAICodex,
            isInteractiveLoginInProgress: false,
            hasPendingCredentialInput: false
        )

        XCTAssertEqual(content.title, "OpenAI Codex 尚未登录")
        XCTAssertEqual(content.connectionLabel, "未登录")
        XCTAssertEqual(content.nextStep, "点击“使用 ChatGPT 登录”完成授权。")
    }

    func testCurrentStatusContentShowsConnectedStandardProviderState() {
        let content = ProviderCurrentStatusPresenter.make(
            currentProvider: .openAI,
            currentModel: "gpt-5.4",
            currentAuthState: OpenClawProviderAuthState(
                kind: "env",
                detail: "sk-test",
                source: "env: OPENAI_API_KEY"
            ),
            selectedProvider: .openAI,
            isInteractiveLoginInProgress: false,
            hasPendingCredentialInput: false
        )

        XCTAssertEqual(content.title, "OpenAI 已连接")
        XCTAssertEqual(content.detail, "当前默认模型是 gpt-5.4。")
        XCTAssertEqual(content.connectionLabel, "已连接")
    }

    func testCurrentStatusContentShowsNeedsConfigurationForStandardProviderWithoutAuth() {
        let content = ProviderCurrentStatusPresenter.make(
            currentProvider: .anthropic,
            currentModel: "claude-sonnet-4-6",
            currentAuthState: OpenClawProviderAuthState(
                kind: "missing",
                detail: "missing",
                source: nil
            ),
            selectedProvider: .anthropic,
            isInteractiveLoginInProgress: false,
            hasPendingCredentialInput: false
        )

        XCTAssertEqual(content.title, "Anthropic 待完成配置")
        XCTAssertEqual(content.detail, "当前还缺少可用认证或模型配置。")
        XCTAssertEqual(content.connectionLabel, "待配置")
        XCTAssertEqual(content.nextStep, "在下方填写必要信息后点击“保存到 OpenClaw”。")
    }

    func testCurrentStatusContentUsesPendingInputAsNextStepWhenEditingStandardProvider() {
        let content = ProviderCurrentStatusPresenter.make(
            currentProvider: .openAI,
            currentModel: "gpt-5.4",
            currentAuthState: OpenClawProviderAuthState(
                kind: "env",
                detail: "sk-test",
                source: "env: OPENAI_API_KEY"
            ),
            selectedProvider: .openAI,
            isInteractiveLoginInProgress: false,
            hasPendingCredentialInput: true
        )

        XCTAssertEqual(content.nextStep, "检测到新的 API Key 输入，点击“保存到 OpenClaw”后生效。")
    }
}
