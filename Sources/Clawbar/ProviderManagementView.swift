import SwiftUI

enum ProviderKind: String, CaseIterable, Identifiable {
    case openAI = "openai"
    case openAICodex = "openai-codex"
    case anthropic = "anthropic"
    case openRouter = "openrouter"
    case liteLLM = "litellm"
    case ollama = "ollama"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .openAICodex:
            "OpenAI Codex"
        case .anthropic:
            "Anthropic"
        case .openRouter:
            "OpenRouter"
        case .liteLLM:
            "LiteLLM"
        case .ollama:
            "Ollama"
        case .custom:
            "Custom"
        }
    }

    var systemImageName: String {
        switch self {
        case .openAI:
            "sparkles"
        case .openAICodex:
            "person.crop.circle.badge.checkmark"
        case .anthropic:
            "text.bubble"
        case .openRouter:
            "network"
        case .liteLLM:
            "bolt.horizontal"
        case .ollama:
            "shippingbox.fill"
        case .custom:
            "slider.horizontal.3"
        }
    }

    var accentColor: Color {
        switch self {
        case .openAI:
            Color(red: 0.12, green: 0.62, blue: 0.49)
        case .openAICodex:
            Color(red: 0.07, green: 0.56, blue: 0.62)
        case .anthropic:
            Color(red: 0.76, green: 0.55, blue: 0.30)
        case .openRouter:
            Color(red: 0.31, green: 0.56, blue: 0.98)
        case .liteLLM:
            Color(red: 0.52, green: 0.46, blue: 0.94)
        case .ollama:
            Color(red: 0.26, green: 0.63, blue: 0.56)
        case .custom:
            Color(red: 0.56, green: 0.56, blue: 0.60)
        }
    }

    var shortDescription: String {
        switch self {
        case .openAI:
            "直接接 OpenAI 官方 API，默认模型走 openai/*。"
        case .openAICodex:
            "通过 OpenClaw 的 ChatGPT OAuth 登录，默认模型走 openai-codex/*。"
        case .anthropic:
            "直接接 Claude 官方 API，默认模型走 anthropic/*。"
        case .openRouter:
            "统一接多家模型，默认接口是 OpenRouter 官方 API。"
        case .liteLLM:
            "通过 LiteLLM Proxy 做统一路由、预算与日志。"
        case .ollama:
            "按 OpenClaw 的原生 Ollama 接入方式走本机或远端实例。"
        case .custom:
            "为自托管或代理网关生成完整的自定义 provider 配置。"
        }
    }

    var suggestedBaseURL: String {
        switch self {
        case .openAI:
            "https://api.openai.com/v1"
        case .openAICodex:
            ""
        case .anthropic:
            "https://api.anthropic.com"
        case .openRouter:
            "https://openrouter.ai/api/v1"
        case .liteLLM:
            "http://localhost:4000"
        case .ollama:
            "http://127.0.0.1:11434"
        case .custom:
            ""
        }
    }

    var suggestedModel: String {
        switch self {
        case .openAI:
            "gpt-5.4"
        case .openAICodex:
            "gpt-5.4"
        case .anthropic:
            "claude-opus-4-6"
        case .openRouter:
            "anthropic/claude-sonnet-4-6"
        case .liteLLM:
            "claude-opus-4-6"
        case .ollama:
            "glm-4.7-flash"
        case .custom:
            ""
        }
    }

    var apiKeyHelpText: String {
        switch self {
        case .openAICodex:
            "OpenClaw 会通过 ChatGPT OAuth 写入 openai-codex 认证，无需手动填写 API Key。"
        case .ollama:
            "Ollama 本地模式可留空；如果实例要求鉴权，再填写。"
        case .custom:
            "留空也能写入自定义 Provider；需要鉴权时再填写。"
        default:
            "保存后会通过 openclaw CLI 写入或修改对应 Provider 配置。"
        }
    }

    var usesInteractiveOAuthFlow: Bool {
        self == .openAICodex
    }
}

struct ProviderManagementView: View {
    @StateObject private var manager = OpenClawProviderManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    private var hasDraftAPIKey: Bool {
        manager.draftAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isBusy: Bool {
        manager.isSaving || manager.isInteractiveLoginInProgress
    }

    private var statusText: String {
        if manager.isInteractiveLoginInProgress {
            return "正在等待 ChatGPT OAuth 完成。"
        }

        if manager.selectedProvider.usesInteractiveOAuthFlow {
            if let authState = manager.detectedAuthState, authState.isConfigured {
                return "\(manager.selectedProvider.displayName) 当前已经有可用认证。"
            }

            return "当前还没有检测到 OpenAI Codex OAuth 认证。"
        }

        if hasDraftAPIKey {
            return "检测到新的 API Key 输入，保存后会通过 openclaw CLI 落盘。"
        }

        if let authState = manager.detectedAuthState, authState.isConfigured {
            return "\(manager.selectedProvider.displayName) 当前已经有可用认证。"
        }

        return "当前 Provider 还没有检测到可用认证。"
    }

    private var statusTint: Color {
        if manager.isInteractiveLoginInProgress {
            return manager.selectedProvider.accentColor
        }

        if hasDraftAPIKey {
            return manager.selectedProvider.accentColor
        }

        if let authState = manager.detectedAuthState, authState.isConfigured {
            return manager.selectedProvider.accentColor
        }

        return Color.orange
    }

    private var statusIconName: String {
        if isBusy {
            return "arrow.triangle.2.circlepath"
        }

        if manager.selectedProvider.usesInteractiveOAuthFlow {
            return manager.detectedAuthState?.isConfigured == true
                ? "person.crop.circle.badge.checkmark"
                : "person.crop.circle.badge.exclamationmark"
        }

        if hasDraftAPIKey {
            return "key.fill"
        }

        return "checkmark.seal.fill"
    }

    private var primaryActionTitle: String {
        if manager.selectedProvider.usesInteractiveOAuthFlow {
            if manager.isInteractiveLoginInProgress {
                return "等待登录完成..."
            }

            return manager.detectedAuthState?.isConfigured == true
                ? "重新使用 ChatGPT 登录"
                : "使用 ChatGPT 登录"
        }

        return "保存到 OpenClaw"
    }

    private var providerSuggestions: [String] {
        if manager.selectedProvider.usesInteractiveOAuthFlow {
            return [
                "点击“使用 ChatGPT 登录”后，Clawbar 会自动打开 Terminal 并运行 OpenClaw 官方登录流程。",
                "OpenClaw 会自动拉起浏览器；如果没有自动打开，请回到 Terminal 按提示继续。",
                "登录成功后，Clawbar 会自动刷新状态，并将默认模型切到 openai-codex/gpt-5.4。",
            ]
        }

        return [
            "如果只是官方 OpenAI / Anthropic API，通常只需要填模型和 API Key。",
            "如果是代理网关或自托管服务，优先填写 Base URL，再由页面走 `openclaw onboard --non-interactive` 生成完整配置。",
            "Ollama 按 OpenClaw 的原生接法走 `http://127.0.0.1:11434`，不要再写 `/v1`。",
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: theme.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    unifiedConfigurationCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .task {
            manager.refreshStatus(syncSelectionWithDefault: true)
        }
        .onChange(of: manager.selectedProvider) { _, _ in
            manager.refreshSelectedProvider()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Provider 管理")
                    .font(.system(size: 30, weight: .semibold))

                Text("直接读取并调用 openclaw CLI，同步默认模型、认证状态和 Provider 覆盖配置。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            providerBadge
        }
    }

    private var unifiedConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.20))
                        .frame(width: 42, height: 42)

                    Image(systemName: statusIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.headline)

                    Text(manager.lastActionDetail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer()

                if manager.isRefreshing || isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(16)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                compactSummaryMetric(title: "默认模型", value: manager.defaultModelRef ?? "未检测到")
                compactSummaryMetric(title: "配置文件", value: manager.configPath ?? "未检测到")
                compactSummaryMetric(title: "OpenClaw CLI", value: manager.binaryPath ?? "未检测到")
                compactSummaryMetric(
                    title: "认证来源",
                    value: authSourceLabel
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("默认 Provider")
                    .font(.headline)

                Picker("默认 Provider", selection: $manager.selectedProvider) {
                    ForEach(ProviderKind.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 14) {
                if manager.selectedProvider.usesInteractiveOAuthFlow {
                    oauthLoginCard
                } else {
                    if manager.selectedProvider == .custom {
                        customCompatibilityPicker
                    }

                    ProviderInputField(
                        title: "Base URL",
                        helpText: baseURLHelpText,
                        text: $manager.draftBaseURL,
                        prompt: manager.selectedProvider.suggestedBaseURL
                    )

                    ProviderInputField(
                        title: "默认模型",
                        helpText: "保存时会额外调用 `openclaw config set agents.defaults.model.primary ...` 保证当前模型生效。",
                        text: $manager.draftModel,
                        prompt: manager.selectedProvider.suggestedModel
                    )

                    ProviderSecureField(
                        title: "API Key",
                        helpText: manager.selectedProvider.apiKeyHelpText,
                        text: $manager.draftAPIKey
                    )
                }
            }

            HStack(spacing: 10) {
                if manager.selectedProvider.usesInteractiveOAuthFlow {
                    Button(primaryActionTitle) {
                        manager.launchOpenAICodexLogin()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(manager.selectedProvider.accentColor)
                    .disabled(isBusy || manager.binaryPath == nil)
                } else {
                    Button("填入建议值") {
                        manager.applySuggestedValues()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(manager.selectedProvider.accentColor)

                    Button(primaryActionTitle) {
                        manager.saveCurrentProvider()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || manager.binaryPath == nil)

                    Button("清空输入") {
                        manager.clearDrafts()
                    }
                    .buttonStyle(.bordered)
                }

                Button("刷新状态") {
                    manager.refreshStatus(syncSelectionWithDefault: false)
                }
                .buttonStyle(.bordered)
                .disabled(manager.isRefreshing || isBusy)

                Spacer()

                Text(manager.selectedProvider.shortDescription)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("接入建议")
                    .font(.headline)

                ForEach(providerSuggestions, id: \.self) { suggestion in
                    suggestionRow(suggestion)
                }
            }
        }
        .padding(20)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: 1)
        )
        .shadow(color: theme.shadowColor, radius: colorScheme == .dark ? 0 : 18, y: colorScheme == .dark ? 0 : 8)
    }

    private var authSourceLabel: String {
        if manager.hasExplicitAPIKeyOverride {
            return "config.apiKey"
        }

        guard let authState = manager.detectedAuthState else {
            return "未检测到"
        }

        if let source = authState.source?.nonEmptyOr(authState.detail) {
            return source
        }

        return authState.detail
    }

    private var baseURLHelpText: String {
        switch manager.selectedProvider {
        case .openAI:
            "留空时只走官方 OpenAI 路径；如果填写，则会按 OpenAI-compatible custom provider 写入。"
        case .openAICodex:
            "OpenAI Codex 通过 ChatGPT OAuth 登录，此处不支持手动 Base URL。"
        case .anthropic:
            "留空时只走官方 Anthropic 路径；如果填写，则会按 Anthropic-compatible custom provider 写入。"
        case .openRouter, .liteLLM:
            "填写后会用 `openclaw onboard --auth-choice custom-api-key` 生成完整 provider 配置。"
        case .ollama:
            "会按 OpenClaw 的原生 Ollama 配置写入；推荐保持为 `http://127.0.0.1:11434`。"
        case .custom:
            "Custom provider 必填；会生成完整的 `models.providers.custom` 配置。"
        }
    }

    private var customCompatibilityPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("兼容协议")
                .font(.headline)

            Picker("兼容协议", selection: $manager.customCompatibility) {
                ForEach(ProviderCustomCompatibility.allCases) { compatibility in
                    Text(compatibility.displayName).tag(compatibility)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var oauthLoginCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录方式")
                .font(.headline)

            Text("OpenAI Codex 通过 OpenClaw 的 ChatGPT OAuth 流程完成认证。Clawbar 会自动打开 Terminal 并调用官方登录命令。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                oauthDetailRow(
                    title: "OpenClaw 命令",
                    value: "openclaw models auth login --provider openai-codex --set-default"
                )
                oauthDetailRow(
                    title: "浏览器回调",
                    value: "http://localhost:1455/auth/callback"
                )
                oauthDetailRow(
                    title: "默认模型",
                    value: "openai-codex/\(manager.selectedProvider.suggestedModel)"
                )
            }
            .padding(14)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func oauthDetailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
        }
    }

    private var providerBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: manager.selectedProvider.systemImageName)
                .font(.system(size: 12, weight: .semibold))

            Text(manager.selectedProvider.displayName)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(manager.selectedProvider.accentColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(manager.selectedProvider.accentColor.opacity(0.15), in: Capsule())
        .overlay(
            Capsule()
                .stroke(manager.selectedProvider.accentColor.opacity(0.35), lineWidth: 1)
        )
    }

    private func compactSummaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func suggestionRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(manager.selectedProvider.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}

private struct ProviderInputField: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let helpText: String
    @Binding var text: String
    let prompt: String

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(helpText)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
        }
    }
}

private struct ProviderSecureField: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let helpText: String
    @Binding var text: String

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(helpText)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            SecureField("", text: $text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
        }
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
