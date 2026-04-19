import SwiftUI

struct HermesManagementView: View {
    @ObservedObject var installer: HermesInstaller
    @ObservedObject var gatewayManager: HermesGatewayManager
    @ObservedObject var tuiManager: HermesTUIManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                runtimeSection
                Divider()
                gatewaySection
                Divider()
                tuiSection
                Divider()
                logsSection
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 620)
        .task {
            await installer.refreshStatus(force: true)
            await gatewayManager.refreshStatus()
        }
    }

    // MARK: - Runtime

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hermes Agent")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(installer.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(installer.detailText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if installer.isRefreshingStatus || installer.isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                runtimeRow(label: "uv", value: installer.uvBinaryPath ?? "未检测到")
                runtimeRow(label: "hermes", value: installer.hermesBinaryPath ?? "未检测到")
                runtimeRow(label: "版本", value: installer.hermesVersion ?? "—")
                runtimeRow(label: "默认模型", value: installer.defaultModel ?? "未配置")
            }
            .padding(12)
            .background(.quaternary.opacity(0.18))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            HStack(spacing: 10) {
                Button(installer.isInstalled ? "重新安装 Hermes" : "安装 Hermes") {
                    Task { await installer.startInstallIfNeeded() }
                }
                .disabled(installer.isBusy)

                Button("升级 Hermes") {
                    Task { await installer.startUpgradeIfNeeded() }
                }
                .disabled(installer.isBusy || !installer.isInstalled)

                Button("卸载 Hermes") {
                    Task { await installer.startUninstallIfNeeded() }
                }
                .disabled(installer.isBusy || !installer.isInstalled)

                Spacer()

                Button("刷新状态") {
                    Task { await installer.refreshStatus(force: true) }
                }
                .disabled(installer.isRefreshingStatus)
            }
        }
    }

    private func runtimeRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }

    // MARK: - Gateway

    private var gatewaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hermes Gateway")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text(gatewayStatusSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if gatewayManager.isBusy {
                    ProgressView().controlSize(.small)
                }
            }

            HStack(spacing: 10) {
                Button("安装服务") {
                    Task { await gatewayManager.install() }
                }
                .disabled(!installer.isInstalled || gatewayManager.isBusy)

                Button(gatewayManager.statusSnapshot.isRunning ? "重启服务" : "启动服务") {
                    Task {
                        if gatewayManager.statusSnapshot.isRunning {
                            await gatewayManager.restart()
                        } else {
                            await gatewayManager.start()
                        }
                    }
                }
                .disabled(!installer.isInstalled || gatewayManager.isBusy)

                Button("停止服务") {
                    Task { await gatewayManager.stop() }
                }
                .disabled(!installer.isInstalled || gatewayManager.isBusy || !gatewayManager.statusSnapshot.isRunning)

                Button("卸载服务") {
                    Task { await gatewayManager.uninstall() }
                }
                .disabled(!installer.isInstalled || gatewayManager.isBusy)

                Spacer()

                Button("打开 config.yaml") {
                    _ = gatewayManager.openConfigFile()
                }
                .disabled(!installer.isInstalled)

                Button("Setup 向导（Terminal）") {
                    tuiManager.launchGatewaySetup()
                }
                .disabled(!installer.isInstalled)
            }

            if let feedback = gatewayManager.lastFeedback {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: feedback.isSuccess ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(feedback.isSuccess ? Color.green : Color.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feedback.summary)
                            .font(.callout)
                            .fontWeight(.medium)
                        Text(feedback.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.quaternary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private var gatewayStatusSummary: String {
        let snapshot = gatewayManager.statusSnapshot
        if !installer.isInstalled {
            return "请先安装 Hermes Agent。"
        }
        if !snapshot.isInstalled {
            return "Gateway 服务未安装。点击「安装服务」即可注册 launchd。"
        }
        if snapshot.isRunning {
            if let pid = snapshot.pid {
                return "Gateway 正在运行（PID \(pid)）。"
            }
            return "Gateway 正在运行。"
        }
        if snapshot.isLoaded {
            return "Gateway 已加载到 launchd，但未运行。"
        }
        return "Gateway 已安装但未启动。"
    }

    // MARK: - TUI

    private var tuiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hermes TUI")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Picker("界面风格", selection: $tuiManager.preferredStyle) {
                    ForEach(HermesTUIStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()

                Button("在 Terminal 中打开") {
                    tuiManager.launchTUI()
                }
                .disabled(!installer.isInstalled)
            }

            if let summary = tuiManager.lastLaunchSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Logs

    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最近一次操作日志")
                    .font(.headline)
                Spacer()
                Text(installer.lastLogURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(installer.logText.isEmpty ? "尚未执行 Hermes 安装/升级/卸载操作。" : installer.logText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .id("hermes-log-bottom")
                }
                .frame(minHeight: 180, maxHeight: 260)
                .background(.quaternary.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .onChange(of: installer.logText) { _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("hermes-log-bottom", anchor: .bottom)
                    }
                }
            }

            if let error = installer.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
