import SwiftUI

struct GatewayManagementView: View {
    @ObservedObject var manager: OpenClawGatewayManager
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ManagementTheme {
        ManagementTheme(colorScheme: colorScheme)
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
                    statusCard
                    actionCard
                    commandOutputCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
        .onAppear {
            manager.refreshStatus()
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gateway 管理")
                    .font(.system(size: 30, weight: .semibold))

                Text("参考 OpenClaw 的后台服务命令，直接管理本机 gateway 的启动、重启与暂停。")
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            statusBadge
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusTint.opacity(0.18))
                        .frame(width: 42, height: 42)

                    Image(systemName: statusIconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(manager.snapshot.title)
                        .font(.headline)

                    Text(manager.snapshot.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    manager.refreshStatus()
                } label: {
                    if manager.isRefreshingStatus {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新状态", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(manager.isRefreshingStatus || manager.isPerformingAction)
            }
            .padding(16)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                statusMetric(title: "服务状态", value: serviceStateLabel)
                statusMetric(title: "运行模式", value: runtimeStateLabel)
                statusMetric(title: "OpenClaw CLI", value: manager.snapshot.binaryPath ?? "未检测到")
                statusMetric(title: "PID", value: manager.snapshot.pid.map(String.init) ?? "无")
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

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务动作")
                .font(.headline)

            Text("按钮分别对应 `openclaw gateway start`、`openclaw gateway restart` 和 `openclaw gateway stop`。")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            HStack(spacing: 12) {
                actionButton(title: "启动", systemImage: "play.fill", tint: Color.green) {
                    manager.perform(.start)
                }
                .disabled(manager.isPerformingAction || manager.snapshot.state == .missing || manager.snapshot.state == .running)

                actionButton(title: "重启", systemImage: "arrow.triangle.2.circlepath", tint: Color.orange) {
                    manager.perform(.restart)
                }
                .disabled(manager.isPerformingAction || manager.snapshot.state == .missing)

                actionButton(title: "暂停", systemImage: "pause.fill", tint: Color.red) {
                    manager.perform(.pause)
                }
                .disabled(manager.isPerformingAction || manager.snapshot.state == .missing || manager.snapshot.state == .stopped)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text(manager.lastActionSummary)
                    .font(.headline)

                Text(manager.lastActionDetail)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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

    private var commandOutputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近命令输出")
                .font(.headline)

            ScrollView {
                Text(manager.lastCommandOutput.nonEmptyOr("等待命令输出..."))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minHeight: 220)
            .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(theme.inputBorder, lineWidth: 1)
            )
        }
        .padding(20)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.cardBorder, lineWidth: 1)
        )
        .shadow(color: theme.shadowColor, radius: colorScheme == .dark ? 0 : 18, y: colorScheme == .dark ? 0 : 8)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIconName)
                .font(.system(size: 12, weight: .semibold))

            Text(manager.snapshot.title)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(statusTint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(statusTint.opacity(0.15), in: Capsule())
        .overlay(
            Capsule()
                .stroke(statusTint.opacity(0.35), lineWidth: 1)
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
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(theme.mutedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if manager.isPerformingAction {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }

                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var statusTint: Color {
        switch manager.snapshot.state {
        case .missing:
            Color.orange
        case .stopped:
            Color.yellow
        case .running:
            Color.green
        case .transitioning:
            Color.blue
        case .unknown:
            Color.gray
        }
    }

    private var statusIconName: String {
        switch manager.snapshot.state {
        case .missing:
            "exclamationmark.triangle.fill"
        case .stopped:
            "pause.circle.fill"
        case .running:
            "play.circle.fill"
        case .transitioning:
            "arrow.triangle.2.circlepath.circle.fill"
        case .unknown:
            "questionmark.circle.fill"
        }
    }

    private var serviceStateLabel: String {
        manager.snapshot.serviceLoaded ? "service loaded" : "service not loaded"
    }

    private var runtimeStateLabel: String {
        manager.snapshot.runtimeStatus?.nonEmptyOr("未返回") ?? "未返回"
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : self
    }
}
