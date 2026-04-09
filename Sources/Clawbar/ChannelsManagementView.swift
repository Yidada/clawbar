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
            "官方插件安装、授权、诊断和启用。"
        case .wechat:
            "打开后按官方流程安装并扫码连接。"
        }
    }
}

struct ChannelsManagementView: View {
    @AppStorage("clawbar.debug.enabled") private var globalDebugEnabled = false
    @AppStorage("clawbar.channels.wechat.enabled") private var wechatEnabled = false
    @AppStorage("clawbar.channels.feishu.logsExpanded") private var feishuLogsExpanded = false

    @StateObject private var feishuManager = OpenClawFeishuChannelManager.shared
    @StateObject private var wechatManager = OpenClawChannelManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    private var enabledCount: Int {
        [feishuManager.snapshot.channelEnabled, wechatManager.isEnabled].filter { $0 }.count
    }

    private var wechatToggleBinding: Binding<Bool> {
        Binding(
            get: { wechatToggleVisualState },
            set: { newValue in
                let previousValue = wechatToggleVisualState
                wechatEnabled = newValue

                guard previousValue != newValue else { return }

                guard newValue else {
                    wechatManager.cancelActiveWeChatFlow()
                    return
                }

                if wechatManager.shouldOfferInstall {
                    wechatManager.installWeChatCapability()
                } else {
                    wechatManager.refreshWeChatStatus()
                }
            }
        )
    }

    private var feishuToggleBinding: Binding<Bool> {
        Binding(
            get: { feishuManager.isEnabled },
            set: { newValue in
                if newValue {
                    guard feishuCanEnableFromToggle else { return }
                    feishuManager.enable()
                } else {
                    feishuManager.disable()
                }
            }
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
                    channelsGrid
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 760)
        .task {
            wechatManager.refreshWeChatStatus()
            feishuManager.refreshStatus()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Channels 管理")
                    .font(.system(size: 30, weight: .semibold))

                Text("集中维护飞书和微信通道；飞书会按官方插件 CLI 的安装、配置和诊断流程图形化引导。")
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

    private var channelsGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                feishuCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                wechatCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(spacing: 14) {
                feishuCard
                wechatCard
            }
        }
    }

    private var feishuCard: some View {
        channelShell(
            kind: .feishu,
            enabled: feishuToggleBinding,
            toggleDisabled: feishuToggleDisabled
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("官方 Feishu 插件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChannelKind.feishu.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ChannelKind.feishu.accentColor.opacity(0.14), in: Capsule())

                    Text(feishuManager.statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(feishuStatusTone)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("当前阶段")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)

                    Text(feishuStatusHeadline)
                        .font(.title3.weight(.semibold))

                    Text(feishuStatusDetail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("机器人绑定")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)

                    Text("仅保留飞书扫码配置/创建机器人；如需更换当前机器人，点击“重新绑定”即可。")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if feishuManager.snapshot.channelBound {
                        Text("当前已检测到可用的 Feishu 机器人配置。顶部开关只控制 channel 的启用与停用，不会改动绑定关系。")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    } else {
                        Text("当前还没有绑定机器人；完成扫码后，Clawbar 会继续安装插件并写入配置。")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                .padding(14)
                .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let qrCodeURL = feishuManager.snapshot.qrCodeURL,
                   let qrURL = URL(string: qrCodeURL) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("飞书扫码")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)

                        HStack(alignment: .center, spacing: 16) {
                            QRCodeImageView(payload: qrCodeURL)
                                .frame(width: 168, height: 168)
                                .padding(10)
                                .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(theme.inputBorder, lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("请直接用飞书扫一扫。")
                                    .font(.subheadline.weight(.medium))

                                Text("扫码后无需再看 Terminal；Clawbar 会自动轮询并继续安装。")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)

                                Link("在浏览器打开二维码链接", destination: qrURL)
                                    .font(.caption.weight(.semibold))
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }

                Button(feishuManager.bindingActionTitle) {
                    feishuManager.startQRCodeBinding()
                }
                .buttonStyle(.borderedProminent)
                .tint(ChannelKind.feishu.accentColor)
                .disabled(feishuSetupActionDisabled)

                feishuAccessConfigurationSection(
                    title: "DM 配置",
                    summary: feishuManager.dmConfigurationSummary,
                    mode: feishuDMModeBinding,
                    openIDsText: feishuDMOpenIDsBinding,
                    specifiedDescription: "默认使用“指定人”模式；如果已识别到当前绑定人的 Open ID，Clawbar 会自动预填。",
                    everyoneDescription: "所有人都可以直接私信机器人。",
                    inputPrompt: "输入允许私信机器人的 Open ID，支持逗号或换行分隔。"
                )

                feishuAccessConfigurationSection(
                    title: "群聊配置",
                    summary: feishuManager.groupConfigurationSummary,
                    mode: feishuGroupModeBinding,
                    openIDsText: feishuGroupOpenIDsBinding,
                    specifiedDescription: "默认使用“指定人 @机器人”模式；只会响应指定人 @机器人的消息。",
                    everyoneDescription: "会响应任何人 @机器人的消息。",
                    inputPrompt: "输入允许在群里 @机器人的 Open ID，支持逗号或换行分隔。",
                    footer: "当前版本统一要求 @机器人，避免群内刷屏。"
                )

                if feishuManager.hasAdvancedGroupRules {
                    Text("检测到更细粒度的群规则；本页只管理全局默认模式，不会清除已有群级覆盖。")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let accessError = feishuManager.accessConfigurationError {
                    Text(accessError)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    Button("保存配置") {
                        feishuManager.saveAccessConfiguration()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ChannelKind.feishu.accentColor)
                    .disabled(feishuAccessConfigurationDisabled)

                    Button("恢复当前配置") {
                        feishuManager.resetAccessConfigurationDraft()
                    }
                    .buttonStyle(.bordered)
                    .disabled(feishuAccessConfigurationResetDisabled)
                }

                if shouldShowFeishuLogs {
                    DisclosureGroup("展开日志", isExpanded: $feishuLogsExpanded) {
                        ScrollView {
                            Text(trimmedNonEmpty(feishuManager.lastCommandOutput) ?? "暂无日志")
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(12)
                        }
                        .frame(minHeight: 120, maxHeight: 220)
                        .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(theme.inputBorder, lineWidth: 1)
                        )
                        .padding(.top, 6)
                    }
                }

                if feishuManager.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var feishuStatusTone: Color {
        switch feishuManager.snapshot.stage {
        case .ready:
            return ChannelKind.feishu.accentColor
        case .diagnose, .preflight:
            return .orange
        case .install, .configure, .verify:
            return theme.secondaryText
        }
    }

    private var feishuSetupActionDisabled: Bool {
        feishuManager.activeAction != nil
    }

    private var feishuCanEnableFromToggle: Bool {
        feishuManager.canToggleChannelEnabled && !feishuManager.isBusy
    }

    private var feishuToggleDisabled: Bool {
        feishuManager.isBusy || (!feishuManager.isEnabled && !feishuCanEnableFromToggle)
    }

    private var shouldShowFeishuLogs: Bool {
        ClawbarDebugOptions.shouldShowDebugUI(globalDebugEnabled: globalDebugEnabled)
    }

    private var wechatCard: some View {
        channelShell(kind: .wechat, enabled: wechatToggleBinding) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("官方 WeixinClawBot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ChannelKind.wechat.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(ChannelKind.wechat.accentColor.opacity(0.14), in: Capsule())

                    if let statusTone = wechatStatusTone {
                        Text(wechatManager.statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusTone)
                    } else {
                        Text(wechatManager.statusLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("当前状态")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)

                    Text(wechatStatusHeadline)
                        .font(.title3.weight(.semibold))

                    Text(wechatStatusDetail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                if let qrCodeURL = wechatManager.runtimeSnapshot.qrCodeURL,
                   let qrURL = URL(string: qrCodeURL),
                   !wechatManager.runtimeSnapshot.connected {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("微信扫码")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)

                        HStack(alignment: .center, spacing: 16) {
                            QRCodeImageView(payload: qrCodeURL)
                                .frame(width: 168, height: 168)
                                .padding(10)
                                .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(theme.inputBorder, lineWidth: 1)
                                )

                            VStack(alignment: .leading, spacing: 8) {
                                Text("请直接用微信扫一扫。")
                                    .font(.subheadline.weight(.medium))

                                Text(wechatManager.runtimeSnapshot.qrExpired ? "二维码过期后会自动刷新。" : "如果二维码失效，后台流程会自动刷新。")
                                    .font(.caption)
                                    .foregroundStyle(theme.secondaryText)

                                Link("在浏览器打开二维码", destination: qrURL)
                                    .font(.caption.weight(.semibold))
                            }

                            Spacer(minLength: 0)
                        }
                    }
                }

                HStack(spacing: 10) {
                    if wechatManager.isFlowActive {
                        Button("取消流程") {
                            wechatManager.cancelActiveWeChatFlow()
                        }
                        .buttonStyle(.bordered)
                    } else if shouldShowInstallButton {
                        Button("开始安装") {
                            wechatManager.installWeChatCapability()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChannelKind.wechat.accentColor)

                        Button("刷新状态") {
                            wechatManager.refreshWeChatStatus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(wechatManager.isRefreshing)
                    } else if shouldShowBindButton {
                        Button("扫码连接") {
                            wechatManager.startWeChatBinding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChannelKind.wechat.accentColor)
                        .disabled(wechatManager.isBusy)

                        Button("刷新状态") {
                            wechatManager.refreshWeChatStatus()
                        }
                        .buttonStyle(.bordered)
                        .disabled(wechatManager.isBusy)
                    } else {
                        Button("刷新状态") {
                            wechatManager.refreshWeChatStatus()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChannelKind.wechat.accentColor)
                        .disabled(wechatManager.isBusy)
                    }
                }

                if wechatManager.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var wechatStatusHeadline: String {
        if wechatManager.isInstalling {
            if wechatManager.runtimeSnapshot.restartingGateway {
                return "正在重启 Gateway"
            }
            if wechatManager.runtimeSnapshot.connected {
                return "微信连接成功"
            }
            if wechatManager.runtimeSnapshot.scanned {
                return "已扫码，等待确认"
            }
            if wechatManager.runtimeSnapshot.qrCodeURL != nil {
                return "请用微信扫码"
            }
            if wechatManager.runtimeSnapshot.pluginReadyForLogin {
                return "正在准备扫码"
            }
            if wechatManager.runtimeSnapshot.pluginInstalled {
                return "插件已安装"
            }
            return "正在安装微信插件"
        }
        if wechatManager.isLaunchingBinding {
            if wechatManager.runtimeSnapshot.connected {
                return "微信连接成功"
            }
            if wechatManager.runtimeSnapshot.scanned {
                return "已扫码，等待确认"
            }
            if wechatManager.runtimeSnapshot.qrCodeURL != nil {
                return "请用微信扫码"
            }
            return "正在准备扫码"
        }
        return wechatManager.steadyStatusHeadline
    }

    private var wechatStatusDetail: String {
        if wechatManager.isInstalling {
            if wechatManager.runtimeSnapshot.restartingGateway {
                return "官方安装器已经完成扫码，正在重启 OpenClaw Gateway。"
            }
            if wechatManager.runtimeSnapshot.connected {
                return "已经识别到微信连接成功，正在完成最后收尾。"
            }
            if wechatManager.runtimeSnapshot.scanned {
                return "请在手机微信里确认授权。"
            }
            if wechatManager.runtimeSnapshot.qrCodeURL != nil {
                return "二维码已提取到当前页面，无需再看 Terminal。"
            }
            if wechatManager.runtimeSnapshot.pluginReadyForLogin {
                return "插件安装完成，正在拉起微信扫码登录。"
            }
            if wechatManager.runtimeSnapshot.pluginInstalled {
                return "已识别到插件安装完成。"
            }
            return "Clawbar 正在后台执行官方安装器。"
        }
        if wechatManager.isLaunchingBinding {
            if wechatManager.runtimeSnapshot.connected {
                return "已经识别到微信连接成功。"
            }
            if wechatManager.runtimeSnapshot.scanned {
                return "请在手机微信里确认授权。"
            }
            if wechatManager.runtimeSnapshot.qrCodeURL != nil {
                return "二维码已提取到当前页面，无需再看 Terminal。"
            }
            return "Clawbar 正在后台发起扫码登录。"
        }
        return wechatManager.steadyStatusDetail
    }

    private var wechatStatusTone: Color? {
        if wechatManager.usesWarningTone {
            return .orange
        }
        if wechatManager.usesSuccessTone {
            return ChannelKind.wechat.accentColor
        }
        return nil
    }

    private var shouldShowBindButton: Bool {
        wechatDesiredState && wechatManager.shouldOfferBind
    }

    private var shouldShowInstallButton: Bool {
        wechatDesiredState && wechatManager.shouldOfferInstall
    }

    private var wechatDesiredState: Bool {
        wechatEnabled || wechatManager.isEnabled || wechatManager.isFlowActive
    }

    private var wechatToggleVisualState: Bool {
        if wechatManager.hasResolvedStatus {
            return wechatManager.isEnabled
        }

        return wechatManager.isFlowActive ? wechatEnabled : false
    }

    private var feishuDMModeBinding: Binding<FeishuAccessMode> {
        Binding(
            get: { feishuManager.dmAccessMode },
            set: { feishuManager.dmAccessMode = $0 }
        )
    }

    private var feishuDMOpenIDsBinding: Binding<String> {
        Binding(
            get: { feishuManager.dmOpenIDsText },
            set: { feishuManager.dmOpenIDsText = $0 }
        )
    }

    private var feishuGroupModeBinding: Binding<FeishuAccessMode> {
        Binding(
            get: { feishuManager.groupAccessMode },
            set: { feishuManager.groupAccessMode = $0 }
        )
    }

    private var feishuGroupOpenIDsBinding: Binding<String> {
        Binding(
            get: { feishuManager.groupOpenIDsText },
            set: { feishuManager.groupOpenIDsText = $0 }
        )
    }

    private var feishuAccessConfigurationDisabled: Bool {
        !feishuManager.canEditAccessConfiguration
    }

    private var feishuAccessConfigurationResetDisabled: Bool {
        feishuAccessConfigurationDisabled || !feishuManager.hasUnsavedAccessConfigurationChanges
    }

    private var feishuStatusHeadline: String {
        feishuManager.displaySummary
    }

    private var feishuStatusDetail: String {
        feishuManager.displayDetail
    }

    private func channelShell<Content: View>(
        kind: ChannelKind,
        enabled: Binding<Bool>,
        toggleDisabled: Bool = false,
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
                    .disabled(toggleDisabled)
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
}
