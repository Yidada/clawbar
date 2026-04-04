import SwiftUI

enum ChannelKind: String, CaseIterable, Identifiable {
    case feishu
    case wechat

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .feishu:
            "飞书"
        case .wechat:
            "微信"
        }
    }

    var systemImageName: String {
        switch self {
        case .feishu:
            "briefcase.fill"
        case .wechat:
            "message.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .feishu:
            Color(red: 0.20, green: 0.66, blue: 0.93)
        case .wechat:
            Color(red: 0.15, green: 0.71, blue: 0.25)
        }
    }

    var descriptionText: String {
        switch self {
        case .feishu:
            "Webhook、应用凭证和群聊路由。"
        case .wechat:
            "按需安装官方 WeixinClawBot，并在需要时单独绑定。"
        }
    }
}

struct ChannelsManagementView: View {
    @AppStorage("clawbar.channels.default") private var defaultChannelRawValue = ChannelKind.feishu.rawValue
    @AppStorage("clawbar.channels.feishu.enabled") private var feishuEnabled = false
    @AppStorage("clawbar.channels.feishu.endpoint") private var feishuEndpoint = ""
    @AppStorage("clawbar.channels.wechat.enabled") private var wechatEnabled = false
    @StateObject private var wechatManager = OpenClawChannelManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    private var defaultChannel: ChannelKind {
        get { ChannelKind(rawValue: defaultChannelRawValue) ?? .feishu }
        nonmutating set { defaultChannelRawValue = newValue.rawValue }
    }

    private var enabledCount: Int {
        [feishuEnabled, wechatEnabled].filter { $0 }.count
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
                    overviewCard
                    channelsGrid
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 760)
        .task {
            wechatManager.refreshWeChatStatus()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Channels 管理")
                    .font(.system(size: 30, weight: .semibold))

                Text("集中维护飞书和微信通道；微信能力与 OpenClaw 主安装解耦，按需安装后再绑定。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("已启用 \(enabledCount) 个")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Color.cyan)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.cyan.opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("接入概览")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                overviewMetric(title: "默认回传 Channel", value: defaultChannel.displayName)
                overviewMetric(title: "已启用", value: "\(enabledCount) / \(ChannelKind.allCases.count)")
                overviewMetric(title: "微信状态", value: wechatManager.statusLabel)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("默认回传入口")
                    .font(.headline)

                Picker("默认回传 Channel", selection: Binding(
                    get: { defaultChannel },
                    set: { defaultChannel = $0 }
                )) {
                    ForEach(ChannelKind.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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

    private var channelsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            feishuCard
            wechatCard
        }
    }

    private var feishuCard: some View {
        channelShell(kind: .feishu, enabled: $feishuEnabled) {
            VStack(alignment: .leading, spacing: 8) {
                Text("接入备注 / Endpoint")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)

                TextField("", text: $feishuEndpoint, prompt: Text("例如 Feishu App ID / Webhook 地址"))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(theme.inputBorder, lineWidth: 1)
                    )
            }

            Text(feishuEnabled ? "当前 Channel 已启用，可作为 OpenClaw 的消息入口候选。" : "当前 Channel 未启用，只保留接入备注。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var wechatCard: some View {
        channelShell(kind: .wechat, enabled: $wechatEnabled) {
            HStack(spacing: 8) {
                Text("官方 WeixinClawBot")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ChannelKind.wechat.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ChannelKind.wechat.accentColor.opacity(0.14), in: Capsule())

                Text(wechatManager.statusLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("微信能力状态")
                    .font(.headline)

                Text(wechatManager.lastActionSummary)
                    .font(.subheadline.weight(.semibold))

                Text(wechatManager.lastActionDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Button("安装微信能力") {
                        wechatManager.installWeChatCapability()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ChannelKind.wechat.accentColor)
                    .disabled(wechatManager.isInstalling || wechatManager.openClawBinaryPath == nil)

                    Button("开始绑定") {
                        wechatManager.startWeChatBinding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        wechatManager.isInstalling ||
                        wechatManager.isLaunchingBinding ||
                        wechatManager.pluginInstalled == false
                    )

                    Button("刷新状态") {
                        wechatManager.refreshWeChatStatus()
                    }
                    .buttonStyle(.bordered)
                    .disabled(wechatManager.isRefreshing || wechatManager.isInstalling || wechatManager.isLaunchingBinding)
                }

                if wechatManager.isInstalling || wechatManager.isLaunchingBinding || wechatManager.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                guideRow("微信能力独立于 OpenClaw 主安装，失败后可在这里单独重试。")
                guideRow("开始绑定后会自动拉起 Terminal，执行 `openclaw channels login --channel openclaw-weixin`。")
                guideRow("用户实际只需要在微信里扫码；当前官方渠道只支持私聊。")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("最近动作输出")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)

                ScrollView {
                    Text(wechatManager.lastCommandOutput.nonEmptyOr("等待执行微信能力安装或绑定命令..."))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 160)
                .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.inputBorder, lineWidth: 1)
                )
            }

            Text(wechatRuntimeSummary)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var wechatRuntimeSummary: String {
        if wechatManager.openClawBinaryPath == nil {
            return "当前设备还没有可用的 OpenClaw CLI，因此暂时无法内置微信能力。"
        }
        if wechatManager.pluginInstalled == false {
            return "微信 Channel 已启用，但官方 WeixinClawBot 还没有安装到当前 OpenClaw 环境。"
        }
        if wechatManager.bindingDetected == false {
            return "微信能力已安装，下一步直接点“开始绑定”，然后用微信扫码。"
        }
        if wechatEnabled == false {
            return "微信能力已就绪，但当前 Clawbar 本地开关未启用。需要时仍可直接重新绑定。"
        }
        return "微信 Channel 已准备好，后续通常只在重新配对时再需要扫码。"
    }

    private func overviewMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)

            Text(value)
                .font(.subheadline)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func channelShell<Content: View>(
        kind: ChannelKind,
        enabled: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(kind.accentColor.opacity(0.18))
                        .frame(width: 36, height: 36)

                    Image(systemName: kind.systemImageName)
                        .foregroundStyle(kind.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(.headline)
                    Text(kind.descriptionText)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            content()
        }
        .padding(18)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(kind.accentColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: theme.shadowColor, radius: colorScheme == .dark ? 0 : 18, y: colorScheme == .dark ? 0 : 8)
    }

    private func guideRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(ChannelKind.wechat.accentColor)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(text)
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
