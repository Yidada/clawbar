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
    @AppStorage("clawbar.channels.default") private var defaultChannelRawValue = ChannelKind.feishu.rawValue
    @AppStorage("clawbar.channels.wechat.enabled") private var wechatEnabled = false
    @AppStorage("clawbar.channels.feishu.logsExpanded") private var feishuLogsExpanded = false

    @StateObject private var feishuManager = OpenClawFeishuChannelManager.shared
    @StateObject private var wechatManager = OpenClawChannelManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    @State private var feishuAppID = ""
    @State private var feishuAppSecret = ""

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
    }

    private var defaultChannel: ChannelKind {
        get { ChannelKind(rawValue: defaultChannelRawValue) ?? .feishu }
        nonmutating set { defaultChannelRawValue = newValue.rawValue }
    }

    private var enabledCount: Int {
        [feishuManager.snapshot.channelEnabled, wechatEnabled].filter { $0 }.count
    }

    private var wechatToggleBinding: Binding<Bool> {
        Binding(
            get: { wechatEnabled },
            set: { newValue in
                let previousValue = wechatEnabled
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
                    feishuManager.enable(using: feishuCredentialsOrNil)
                } else {
                    feishuManager.disable()
                }
            }
        )
    }

    private var feishuSetupModeBinding: Binding<FeishuSetupMode> {
        Binding(
            get: { feishuManager.snapshot.setupMode },
            set: { feishuManager.selectSetupMode($0) }
        )
    }

    private var feishuCredentialsOrNil: FeishuAppCredentials? {
        let credentials = FeishuAppCredentials(appID: feishuAppID, appSecret: feishuAppSecret)
        return feishuManager.snapshot.setupMode == .useProvidedCredentials && credentials.isComplete ? credentials : nil
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

    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("接入概览")
                .font(.headline)

            HStack(alignment: .top, spacing: 12) {
                overviewMetric(title: "默认回传 Channel", value: defaultChannel.displayName)
                overviewMetric(title: "已启用", value: "\(enabledCount) / \(ChannelKind.allCases.count)")
                overviewMetric(title: "飞书状态", value: feishuManager.statusLabel)
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

                if !feishuManager.snapshot.pluginInstalled {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("安装方式")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.secondaryText)

                        Picker("安装方式", selection: feishuSetupModeBinding) {
                            ForEach(feishuSetupModeOptions) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .disabled(feishuManager.isBusy)

                        Text(feishuManager.snapshot.setupMode.detail)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if !feishuManager.snapshot.reusableConfiguredBotAvailable {
                            Text("当前没有检测到可复用的 OpenClaw Feishu 机器人配置。")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                        }
                    }
                    .padding(14)
                    .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if feishuManager.snapshot.setupMode == .useProvidedCredentials,
                   !feishuManager.snapshot.pluginInstalled {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("App ID，例如 cli_xxx", text: $feishuAppID)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(theme.inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(theme.inputBorder, lineWidth: 1)
                            )

                        SecureField("App Secret", text: $feishuAppSecret)
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

                if let qrCodeURL = feishuManager.snapshot.qrCodeURL,
                   let qrURL = URL(string: qrCodeURL),
                   !feishuManager.snapshot.pluginInstalled {
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

                HStack(spacing: 10) {
                    if feishuManager.isOnboardingActive {
                        Button("取消流程") {
                            feishuManager.cancelActiveSetupFlow()
                        }
                        .buttonStyle(.bordered)

                        if let browserURL = feishuManager.snapshot.browserURL,
                           let url = URL(string: browserURL) {
                            Button("在浏览器打开") {
                                openURL(url)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ChannelKind.feishu.accentColor)
                        }
                    } else {
                        Button(feishuManager.primaryActionTitle) {
                            if feishuManager.snapshot.stage == .configure,
                               let browserURL = feishuManager.snapshot.browserURL,
                               let url = URL(string: browserURL) {
                                openURL(url)
                            } else {
                                feishuManager.runPrimaryAction(existingAppCredentials: feishuCredentialsOrNil)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ChannelKind.feishu.accentColor)
                        .disabled(feishuPrimaryActionDisabled)
                    }

                    Button("刷新状态") {
                        feishuManager.refreshStatus()
                    }
                    .buttonStyle(.bordered)
                    .disabled(feishuManager.isBusy)
                }

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

    private var feishuPrimaryActionDisabled: Bool {
        if feishuManager.isBusy {
            return true
        }

        if feishuManager.primaryAction == .enable {
            switch feishuManager.snapshot.setupMode {
            case .reuseConfiguredBot:
                return !feishuManager.snapshot.reusableConfiguredBotAvailable
            case .useProvidedCredentials:
                return feishuCredentialsOrNil == nil
            case .createOrConfigureNewBot:
                return false
            }
        }

        return false
    }

    private var feishuCanEnableFromToggle: Bool {
        feishuManager.canStartEnableFlow && !feishuPrimaryActionDisabled
    }

    private var feishuToggleDisabled: Bool {
        feishuManager.isBusy || (!feishuManager.isEnabled && !feishuCanEnableFromToggle)
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
        wechatEnabled && wechatManager.shouldOfferBind
    }

    private var shouldShowInstallButton: Bool {
        wechatEnabled && wechatManager.shouldOfferInstall
    }

    private var feishuSetupModeOptions: [FeishuSetupMode] {
        if feishuManager.snapshot.reusableConfiguredBotAvailable {
            return FeishuSetupMode.allCases
        }
        return FeishuSetupMode.allCases.filter { $0 != .reuseConfiguredBot }
    }

    private var feishuStatusHeadline: String {
        feishuManager.snapshot.summary
    }

    private var feishuStatusDetail: String {
        feishuManager.snapshot.detail
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
