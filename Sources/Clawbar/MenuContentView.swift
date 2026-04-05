import AppKit
import SwiftUI
import ClawbarKit

struct MenuContentView: View {
    let model: MenuContentModel
    @ObservedObject var installer: OpenClawInstaller
    @ObservedObject var gatewayManager: OpenClawGatewayManager
    @ObservedObject var tuiManager: OpenClawTUIManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.title)
                .font(.headline)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .title))

            Text(model.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .subtitle))

            Divider()

            if installer.isInstalled {
                openClawInfoSection

                Button(tuiManager.isLaunching ? "正在打开 TUI..." : model.tuiDebugButtonTitle) {
                    launchOpenClawTUI()
                }
                .disabled(tuiManager.isLaunching)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .tuiDebugButton))

                Button(installer.isUninstalling ? "卸载中..." : model.uninstallButtonTitle) {
                    uninstallOpenClaw()
                }
                .disabled(installer.isBusy)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .uninstallButton))

                Divider()
            } else {
                Button(installer.isInstalling ? "安装中..." : model.installButtonTitle) {
                    installOpenClaw()
                }
                .disabled(installer.isBusy)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .installButton))
            }

            Button(model.managementButtonTitle) {
                openApplicationManagement()
            }
            .accessibilityIdentifier(model.accessibilityIdentifier(for: .managementButton))

            Button(model.quitButtonTitle) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .accessibilityIdentifier(model.accessibilityIdentifier(for: .quitButton))
        }
        .padding(12)
        .frame(width: model.width)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            installer.refreshInstallationStatus()
        }
    }

    private var openClawInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 8, height: 8)

                Text("OpenClaw")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier(model.accessibilityIdentifier(for: .openClawTitle))

                if installer.isRefreshingStatus {
                    Spacer()

                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let binaryPath = installer.installedBinaryPath {
                Text(binaryPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(model.accessibilityIdentifier(for: .openClawBinaryPath))
            }

            Text(installer.detailText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .openClawDetail))

            if let healthSnapshot = installer.healthSnapshot {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(healthSnapshot.dimensions) { dimension in
                        healthDimensionRow(dimension)
                    }
                }
            }

            if let statusExcerpt = installer.statusExcerpt {
                Text(statusExcerpt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier(model.accessibilityIdentifier(for: .openClawExcerpt))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(model.accessibilityIdentifier(for: .openClawSection))
    }

    private func installOpenClaw() {
        openWindow(id: ClawbarWindow.openClawInstallID)
        NSApp.activate(ignoringOtherApps: true)
        installer.startInstallIfNeeded()
    }

    private func uninstallOpenClaw() {
        openWindow(id: ClawbarWindow.openClawInstallID)
        NSApp.activate(ignoringOtherApps: true)
        installer.startUninstallIfNeeded()
    }

    private func launchOpenClawTUI() {
        tuiManager.launchTUI()
    }

    private func openApplicationManagement() {
        gatewayManager.refreshStatus()
        openWindow(id: ClawbarWindow.applicationManagementID)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusIndicatorColor: Color {
        if installer.isRefreshingStatus {
            return .orange
        }

        switch installer.healthSnapshot?.overallLevel {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .unknown, .none:
            return .gray
        }
    }

    @ViewBuilder
    private func healthDimensionRow(_ dimension: OpenClawHealthDimensionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 8) {
                Text(dimension.dimension.title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(dimension.summary)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(dimension.statusLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(healthLevelColor(dimension.level))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(healthLevelColor(dimension.level).opacity(0.14))
                    .clipShape(Capsule())
            }

            Text(dimension.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
        }
        .padding(.vertical, 2)
    }

    private func healthLevelColor(_ level: OpenClawHealthLevel) -> Color {
        switch level {
        case .healthy:
            .green
        case .warning:
            .orange
        case .critical:
            .red
        case .unknown:
            .gray
        }
    }
}
