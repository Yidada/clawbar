import SwiftUI

struct ProviderManagementView: View {
    @StateObject private var providerManager = OpenClawProviderManager.shared
    @StateObject private var ollamaManager = EmbeddedOllamaManager.shared
    @State private var isAdvancedInfoExpanded = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    private var isBusy: Bool {
        providerManager.isSaving || ollamaManager.isPreparing
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
                    runtimeCard
                    modelCard
                    bindingCard
                    activityCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 680)
        .task {
            ollamaManager.refreshStatus()
            providerManager.refreshStatus()
            providerManager.bootstrapIfPossible(reason: "provider.view")
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ollama / Gemma 4")
                    .font(.system(size: 30, weight: .semibold))

                Text("Clawbar 会优先使用内置 Ollama runtime；缺失时可下载安装，并把 OpenClaw 固定到 ollama/gemma4。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("Gemma 4")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color(red: 0.26, green: 0.63, blue: 0.56))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(red: 0.26, green: 0.63, blue: 0.56).opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(red: 0.26, green: 0.63, blue: 0.56).opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var runtimeCard: some View {
        statusCard(
            title: "Ollama CLI / Runtime",
            statusLabel: ollamaManager.runtimeState.statusLabel,
            detail: ollamaManager.runtimeSummary,
            iconName: runtimeIconName,
            tint: runtimeTint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statusMetric(title: "运行状态", value: ollamaManager.runtimeState.title)
                statusMetric(title: "CLI 路径", value: ollamaManager.cliPath ?? "未检测到")
                statusMetric(title: "安装目录", value: ollamaManager.managedRuntimePath)
                statusMetric(title: "服务地址", value: EmbeddedOllamaManager.defaultBaseURL.absoluteString)
            }
        }
    }

    private var modelCard: some View {
        statusCard(
            title: "Gemma 4",
            statusLabel: ollamaManager.modelState.statusLabel,
            detail: ollamaManager.modelSummary,
            iconName: modelIconName,
            tint: modelTint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statusMetric(title: "模型状态", value: ollamaManager.modelState.title)
                statusMetric(title: "固定模型", value: EmbeddedOllamaManager.supportedModelID)
                statusMetric(title: "模型目录", value: ollamaManager.managedModelsPath)
            }
        }
    }

    private var bindingCard: some View {
        statusCard(
            title: "OpenClaw 绑定",
            statusLabel: providerManager.bindingState.statusLabel,
            detail: providerManager.configSummary,
            iconName: bindingIconName,
            tint: bindingTint
        ) {
            VStack(alignment: .leading, spacing: 12) {
                statusMetric(title: "绑定状态", value: providerManager.bindingState.title)
                statusMetric(title: "当前默认模型", value: providerManager.currentModelLabel)
                statusMetric(title: "认证来源", value: authSourceLabel)
            }
        }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                Text("恢复与诊断")
                    .font(.headline)

                Spacer()

                Button {
                    ollamaManager.refreshStatus()
                    providerManager.refreshStatus()
                } label: {
                    if ollamaManager.isRefreshing || providerManager.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || ollamaManager.isRefreshing || providerManager.isRefreshing)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(providerManager.lastActionSummary)
                    .font(.subheadline.weight(.medium))

                Text(providerManager.lastActionDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(primaryOllamaActionTitle) {
                    ollamaManager.prepareRuntimeAndModel()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button(providerManager.isSaving ? "恢复中..." : "恢复 Gemma 4 配置") {
                    providerManager.restoreGemma4Configuration()
                }
                .buttonStyle(.bordered)
                .disabled(isBusy)

                Spacer()
            }

            DisclosureGroup("高级信息", isExpanded: $isAdvancedInfoExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    advancedInfoRow(title: "OpenClaw CLI", value: providerManager.binaryPath ?? "未检测到")
                    advancedInfoRow(title: "OpenClaw 配置", value: providerManager.configPath ?? "未检测到")
                    advancedInfoRow(title: "Ollama CLI", value: ollamaManager.cliPath ?? "未检测到")
                    advancedInfoRow(title: "Ollama 安装目录", value: ollamaManager.managedRuntimePath)
                    advancedInfoRow(title: "固定模型引用", value: OpenClawProviderManager.supportedModelReference)
                    advancedInfoRow(title: "最近命令输出", value: providerManager.lastCommandOutput.nonEmptyOr(ollamaManager.lastCommandOutput.nonEmptyOr("暂无输出")))
                }
                .padding(.top, 12)
            }
            .font(.subheadline)
            .tint(theme.secondaryText)
        }
        .padding(20)
        .cardStyle(theme: theme, colorScheme: colorScheme)
    }

    private var authSourceLabel: String {
        if let source = providerManager.activeAuthState?.source?.nonEmptyOr(providerManager.activeAuthState?.detail ?? "未检测到") {
            return source
        }
        return providerManager.activeAuthState?.detail ?? "未检测到"
    }

    private var primaryOllamaActionTitle: String {
        if ollamaManager.isPreparing {
            return ollamaManager.needsRuntimeInstall ? "安装中..." : "准备中..."
        }
        return ollamaManager.needsRuntimeInstall ? "安装 Ollama CLI" : "准备 / 重新准备 Ollama"
    }

    private var runtimeTint: Color {
        switch ollamaManager.runtimeState {
        case .ready:
            Color.green
        case .starting:
            Color.orange
        case .missing, .failed:
            Color.red
        }
    }

    private var modelTint: Color {
        switch ollamaManager.modelState {
        case .ready:
            Color.green
        case .pulling:
            Color.orange
        case .missing, .failed:
            Color.red
        case .unknown:
            theme.secondaryText
        }
    }

    private var bindingTint: Color {
        switch providerManager.bindingState {
        case .ready:
            Color.green
        case .applying, .waitingForOllama:
            Color.orange
        case .drift, .needsConfiguration, .openClawMissing, .failed:
            Color.red
        }
    }

    private var runtimeIconName: String {
        switch ollamaManager.runtimeState {
        case .ready:
            "checkmark.circle.fill"
        case .starting:
            "arrow.triangle.2.circlepath"
        case .missing, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var modelIconName: String {
        switch ollamaManager.modelState {
        case .ready:
            "shippingbox.fill"
        case .pulling:
            "arrow.down.circle.fill"
        case .missing, .failed:
            "exclamationmark.triangle.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var bindingIconName: String {
        switch providerManager.bindingState {
        case .ready:
            "link.circle.fill"
        case .applying:
            "arrow.triangle.2.circlepath.circle.fill"
        case .waitingForOllama:
            "clock.arrow.circlepath"
        case .drift, .needsConfiguration, .openClawMissing, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private func statusCard<Content: View>(
        title: String,
        statusLabel: String,
        detail: String,
        iconName: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.20))
                        .frame(width: 44, height: 44)

                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(statusLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tint.opacity(0.12), in: Capsule())
            }

            content()
        }
        .padding(20)
        .cardStyle(theme: theme, colorScheme: colorScheme)
    }

    private func statusMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.subheadline)
                .textSelection(.enabled)
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
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmedNonEmpty(self) ?? fallback
    }
}

private extension View {
    func cardStyle(theme: ManagementTheme, colorScheme: ColorScheme) -> some View {
        background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.cardBorder, lineWidth: 1)
            )
            .shadow(color: theme.shadowColor, radius: colorScheme == .dark ? 8 : 18, y: 8)
    }
}
