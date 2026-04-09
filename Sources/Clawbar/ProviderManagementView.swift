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
            "使用 OpenAI 官方 API。"
        case .openAICodex:
            "通过 ChatGPT 登录使用 OpenAI Codex。"
        case .anthropic:
            "使用 Anthropic 官方 API。"
        case .openRouter:
            "通过 OpenRouter 使用多家模型。"
        case .liteLLM:
            "通过 LiteLLM 代理统一接入模型。"
        case .ollama:
            "连接本地或远端的 Ollama 服务。"
        case .custom:
            "连接自托管或代理模型服务。"
        }
    }

    var apiKeyHelpText: String {
        switch self {
        case .openAICodex:
            "OpenAI Codex 通过 ChatGPT 登录，无需手动填写 API Key。"
        case .ollama:
            "本地 Ollama 通常不需要 API Key；只有服务要求鉴权时再填写。"
        case .custom:
            "如果你的服务需要鉴权，再填写 API Key。"
        default:
            "如需使用官方 API，请填写对应 API Key。"
        }
    }

    var usesInteractiveOAuthFlow: Bool {
        self == .openAICodex
    }
}

enum ProviderStatusTone: Equatable {
    case accent
    case warning
    case neutral
}

struct ProviderCurrentStatusContent: Equatable {
    let title: String
    let detail: String
    let connectionLabel: String
    let nextStep: String
    let iconName: String
    let tone: ProviderStatusTone
}

enum ProviderCurrentStatusPresenter {
    static func make(
        currentProvider: ProviderKind?,
        currentModel: String?,
        currentAuthState: OpenClawProviderAuthState?,
        selectedProvider: ProviderKind,
        isInteractiveLoginInProgress: Bool,
        hasPendingCredentialInput: Bool
    ) -> ProviderCurrentStatusContent {
        if isInteractiveLoginInProgress {
            return ProviderCurrentStatusContent(
                title: "正在连接 OpenAI Codex",
                detail: "等待你在浏览器完成 ChatGPT 登录。",
                connectionLabel: "登录中",
                nextStep: "如果浏览器没有自动打开，请回到 Terminal 按提示继续。",
                iconName: "arrow.triangle.2.circlepath",
                tone: .accent
            )
        }

        guard let currentProvider else {
            let nextStep = selectedProvider.usesInteractiveOAuthFlow
                ? "点击“使用 ChatGPT 登录”完成初始化。"
                : "先填写必要信息，再保存到 OpenClaw。"
            return ProviderCurrentStatusContent(
                title: "尚未设置默认 Provider",
                detail: "先在下方完成一次配置，之后这里会显示当前生效状态。",
                connectionLabel: "未设置",
                nextStep: nextStep,
                iconName: "slider.horizontal.3",
                tone: .warning
            )
        }

        let hasCurrentAuth = currentAuthState?.isConfigured == true
        let currentModelLabel = currentModel?.trimmedNonEmpty

        if hasCurrentAuth {
            let detail = currentModelLabel.map { "当前默认模型是 \($0)。" } ?? "\(currentProvider.displayName) 当前已经可以使用。"
            return ProviderCurrentStatusContent(
                title: "\(currentProvider.displayName) 已连接",
                detail: detail,
                connectionLabel: "已连接",
                nextStep: nextStep(
                    currentProvider: currentProvider,
                    selectedProvider: selectedProvider,
                    hasPendingCredentialInput: hasPendingCredentialInput,
                    fallback: "如需切换 Provider 或模型，在下方修改后保存。"
                ),
                iconName: currentProvider.systemImageName,
                tone: .accent
            )
        }

        if currentProvider.usesInteractiveOAuthFlow {
            return ProviderCurrentStatusContent(
                title: "\(currentProvider.displayName) 尚未登录",
                detail: "通过 ChatGPT 登录后即可开始使用。",
                connectionLabel: "未登录",
                nextStep: nextStep(
                    currentProvider: currentProvider,
                    selectedProvider: selectedProvider,
                    hasPendingCredentialInput: hasPendingCredentialInput,
                    fallback: "点击“使用 ChatGPT 登录”完成授权。"
                ),
                iconName: "person.crop.circle.badge.exclamationmark",
                tone: .warning
            )
        }

        return ProviderCurrentStatusContent(
            title: "\(currentProvider.displayName) 待完成配置",
            detail: "当前还缺少可用认证或模型配置。",
            connectionLabel: "待配置",
            nextStep: nextStep(
                currentProvider: currentProvider,
                selectedProvider: selectedProvider,
                hasPendingCredentialInput: hasPendingCredentialInput,
                fallback: "在下方填写必要信息后点击“保存到 OpenClaw”。"
            ),
            iconName: "key.fill",
            tone: .warning
        )
    }

    private static func nextStep(
        currentProvider: ProviderKind,
        selectedProvider: ProviderKind,
        hasPendingCredentialInput: Bool,
        fallback: String
    ) -> String {
        if hasPendingCredentialInput && !selectedProvider.usesInteractiveOAuthFlow {
            return "检测到新的 API Key 输入，点击“保存到 OpenClaw”后生效。"
        }

        guard currentProvider != selectedProvider else {
            return fallback
        }

        if selectedProvider.usesInteractiveOAuthFlow {
            return "你正在配置 \(selectedProvider.displayName)。完成登录后会切换默认 Provider。"
        }

        return "你正在配置 \(selectedProvider.displayName)。填写后保存会切换默认 Provider。"
    }
}

struct ProviderManagementView: View {
    @StateObject private var manager = OpenClawProviderManager.shared
    @State private var isAdvancedInfoExpanded = false
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

    private var currentStatusContent: ProviderCurrentStatusContent {
        ProviderCurrentStatusPresenter.make(
            currentProvider: manager.activeProvider,
            currentModel: manager.activeModelDisplay,
            currentAuthState: manager.activeAuthState,
            selectedProvider: manager.selectedProvider,
            isInteractiveLoginInProgress: manager.isInteractiveLoginInProgress,
            hasPendingCredentialInput: hasDraftAPIKey
        )
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
                    currentStatusCard
                    configurationCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 680)
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

                Text("先看当前生效状态，再在下方切换 Provider 和更新配置。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            providerBadge
        }
    }

    private var currentStatusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.20))
                        .frame(width: 44, height: 44)

                    Image(systemName: currentStatusContent.iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentStatusContent.title)
                        .font(.headline)

                    Text(currentStatusContent.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    manager.refreshStatus(syncSelectionWithDefault: true)
                } label: {
                    if manager.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(manager.isRefreshing || isBusy)
            }
            .padding(16)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                statusMetric(title: "当前 Provider", value: currentProviderLabel)
                statusMetric(title: "当前模型", value: currentModelLabel)
                statusMetric(title: "连接状态", value: currentStatusContent.connectionLabel)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("下一步")
                    .font(.headline)

                Text(currentStatusContent.nextStep)
                    .font(.subheadline)

                ForEach(shortGuidance, id: \.self) { guidance in
                    suggestionRow(guidance)
                }
            }

            if shouldShowRecentActivity {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最近操作")
                        .font(.headline)

                    Text(manager.lastActionSummary)
                        .font(.subheadline.weight(.medium))

                    Text(manager.lastActionDetail)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            DisclosureGroup("高级信息", isExpanded: $isAdvancedInfoExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    advancedInfoRow(title: "配置文件", value: manager.configPath ?? "未检测到")
                    advancedInfoRow(title: "OpenClaw CLI", value: manager.binaryPath ?? "未检测到")
                    advancedInfoRow(title: "当前认证来源", value: currentAuthSourceLabel)

                    if manager.selectedProvider.usesInteractiveOAuthFlow {
                        Divider()

                        advancedInfoRow(
                            title: "登录命令",
                            value: "openclaw models auth login --provider openai-codex --set-default"
                        )
                        advancedInfoRow(
                            title: "浏览器回调",
                            value: "http://localhost:1455/auth/callback"
                        )
                        advancedInfoRow(
                            title: "默认模型",
                            value: "openai-codex/gpt-5.4"
                        )
                    }
                }
                .padding(.top, 12)
            }
            .font(.subheadline)
            .tint(theme.secondaryText)
        }
        .padding(20)
        .cardStyle(theme: theme, colorScheme: colorScheme)
    }

    private var configurationCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("配置与切换")
                    .font(.headline)

                Text(manager.selectedProvider.shortDescription)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
                        text: $manager.draftBaseURL
                    )

                    ProviderInputField(
                        title: "默认模型",
                        helpText: "保存后会切换为当前默认模型。",
                        text: $manager.draftModel
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
            }
        }
        .padding(20)
        .cardStyle(theme: theme, colorScheme: colorScheme)
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

    private var currentProviderLabel: String {
        manager.activeProvider?.displayName ?? "未设置"
    }

    private var currentModelLabel: String {
        manager.activeModelDisplay ?? manager.defaultModelRef ?? "未设置"
    }

    private var currentAuthSourceLabel: String {
        if manager.activeProvider == manager.selectedProvider && manager.hasExplicitAPIKeyOverride {
            return "config.apiKey"
        }

        guard let authState = manager.activeAuthState else {
            return "未检测到"
        }

        if let source = authState.source?.nonEmptyOr(authState.detail) {
            return source
        }

        return authState.detail
    }

    private var shouldShowRecentActivity: Bool {
        manager.isSaving ||
            manager.isRefreshing ||
            manager.isInteractiveLoginInProgress ||
            manager.lastActionSummary.contains("失败") ||
            manager.lastActionSummary.contains("超时") ||
            manager.lastActionSummary.contains("未检测到")
    }

    private var statusTint: Color {
        switch currentStatusContent.tone {
        case .accent:
            return manager.selectedProvider.accentColor
        case .warning:
            return Color.orange
        case .neutral:
            return theme.secondaryText
        }
    }

    private var shortGuidance: [String] {
        switch manager.selectedProvider {
        case .openAICodex:
            return [
                "通过 ChatGPT 登录即可使用 OpenAI Codex。",
                "登录完成后，页面会自动刷新并同步状态。",
            ]
        case .openAI, .anthropic:
            return [
                "通常只需要填写默认模型和 API Key。",
                "如果你走代理地址，再补充 Base URL。",
            ]
        case .openRouter, .liteLLM:
            return [
                "如果平台已经给出模型名称，直接填在默认模型即可。",
                "只有使用自定义接入地址时才需要填写 Base URL。",
            ]
        case .ollama:
            return [
                "本地 Ollama 一般使用 `http://127.0.0.1:11434`。",
                "确认模型名称后保存即可切换默认模型。",
            ]
        case .custom:
            return [
                "请先确认服务地址，再填写模型名称。",
                "如果服务要求鉴权，再补充 API Key。",
            ]
        }
    }

    private var baseURLHelpText: String {
        switch manager.selectedProvider {
        case .openAI:
            "直接使用 OpenAI 官方 API 时可留空；如果走代理地址，再填写。"
        case .openAICodex:
            "OpenAI Codex 通过 ChatGPT 登录，此处不需要填写。"
        case .anthropic:
            "直接使用 Anthropic 官方 API 时可留空；如果走代理地址，再填写。"
        case .openRouter, .liteLLM:
            "只有在你使用自定义接入地址时才需要填写。"
        case .ollama:
            "本地 Ollama 一般使用 `http://127.0.0.1:11434`。"
        case .custom:
            "请填写你的服务地址。"
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

            Text(oauthSummaryText)
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                suggestionRow("点击按钮后，Clawbar 会帮你打开登录流程。")
                suggestionRow("完成浏览器授权后，状态会自动刷新。")
            }
            .padding(14)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var oauthSummaryText: String {
        if manager.detectedAuthState?.isConfigured == true {
            return "当前已经完成 ChatGPT 登录。如需切换账号，可以重新登录。"
        }

        return "OpenAI Codex 通过 ChatGPT 登录完成认证，不需要手动填写 API Key。"
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

    private func statusMetric(title: String, value: String) -> some View {
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

    private func advancedInfoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
}

private struct ProviderInputField: View {
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

            TextField("", text: $text)
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

private extension View {
    func cardStyle(theme: ManagementTheme, colorScheme: ColorScheme) -> some View {
        background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
            .shadow(
                color: theme.shadowColor,
                radius: colorScheme == .dark ? 0 : 18,
                y: colorScheme == .dark ? 0 : 8
            )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
