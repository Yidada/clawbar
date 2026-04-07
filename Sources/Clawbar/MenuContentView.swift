import AppKit
import SwiftUI
import ClawbarKit

struct MenuContentView: View {
    let model: MenuContentModel
    @ObservedObject var installer: OpenClawInstaller
    @ObservedObject var gatewayManager: OpenClawGatewayManager
    @ObservedObject var tuiManager: OpenClawTUIManager
    @ObservedObject var applicationManagementRouter: ApplicationManagementRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    private var theme: MenuBarTheme {
        MenuBarTheme(colorScheme: colorScheme)
    }

    private var snapshot: MenuPanelSnapshot {
        MenuPanelSnapshotFactory.make(
            model: model,
            isInstalled: installer.isInstalled,
            isBusy: installer.isBusy,
            isRefreshingStatus: installer.isRefreshingStatus,
            lastStatusRefreshDate: installer.lastStatusRefreshDate,
            statusText: installer.statusText,
            detailText: installer.detailText,
            installedBinaryPath: installer.installedBinaryPath,
            statusExcerpt: installer.statusExcerpt,
            healthSnapshot: installer.healthSnapshot
        )
    }

    var body: some View {
        ZStack {
            theme.chromeBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                headerSection

                if !snapshot.rows.isEmpty {
                    statusRowsSection
                }

                if let binaryPath = snapshot.binaryPath {
                    binaryPathSection(binaryPath)
                }

                actionSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
        }
        .frame(width: model.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.title)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .accessibilityIdentifier(model.accessibilityIdentifier(for: .headerTitle))

                    Text(snapshot.subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(model.accessibilityIdentifier(for: .headerSubtitle))
                }

                Spacer(minLength: 10)

                refreshButton
            }

            HStack(spacing: 6) {
                if showsInitialRefreshIndicator {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.accent)
                } else {
                    Circle()
                        .fill(theme.pillForeground(for: overallHealthLevel))
                        .frame(width: 8, height: 8)
                }

                if let metadata = snapshot.metadata {
                    Text(metadata)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier(model.accessibilityIdentifier(for: .headerMetadata))
                }
            }
        }
    }

    private var refreshButton: some View {
        Button {
            installer.refreshInstallationStatus(force: true)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.rowBackground)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.panelBorder.opacity(0.85), lineWidth: 1)

                if installer.isRefreshingStatus {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.accent)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(theme.actionIcon)
                }
            }
            .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .disabled(installer.isRefreshingStatus || installer.isBusy)
        .help("刷新状态")
        .accessibilityLabel(Text("刷新状态"))
        .accessibilityIdentifier(model.accessibilityIdentifier(for: .refreshButton))
    }

    private var statusRowsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            divider

            ForEach(snapshot.rows) { row in
                statusRow(row)
                    .accessibilityIdentifier(model.accessibilityIdentifier(for: accessibilityElement(for: row.dimension)))
            }
        }
    }

    private func binaryPathSection(_ binaryPath: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            divider

            Text(binaryPath)
                .font(.system(size: 11.5, weight: .regular))
                .foregroundStyle(theme.tertiaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .binaryPath))
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            divider

            if snapshot.showsInstallAction {
                actionButton(
                    title: installer.isInstalling ? "安装中…" : model.installButtonTitle,
                    systemImage: "arrow.down.circle",
                    trailingText: nil,
                    isDisabled: installer.isBusy,
                    accessibilityElement: .installButton,
                    action: installOpenClaw
                )
            }

            if snapshot.showsUpgradeAction {
                actionButton(
                    title: upgradeButtonTitle,
                    systemImage: "arrow.triangle.2.circlepath.circle",
                    trailingText: nil,
                    isDisabled: isUpgradeActionDisabled,
                    accessibilityElement: .upgradeButton,
                    action: upgradeOpenClaw
                )
            }

            if snapshot.showsTUIDebugAction {
                actionButton(
                    title: tuiManager.isLaunching ? "正在打开 TUI…" : model.tuiDebugButtonTitle,
                    systemImage: "terminal",
                    trailingText: nil,
                    isDisabled: tuiManager.isLaunching,
                    accessibilityElement: .tuiDebugButton,
                    action: launchOpenClawTUI
                )
            }

            if snapshot.showsSettingsAction {
                actionButton(
                    title: model.managementButtonTitle,
                    systemImage: "gearshape",
                    trailingText: nil,
                    isDisabled: false,
                    accessibilityElement: .managementButton,
                    action: openApplicationManagement
                )
            }

            if snapshot.showsUninstallAction {
                actionButton(
                    title: installer.isUninstalling ? "卸载中…" : model.uninstallButtonTitle,
                    systemImage: "trash",
                    trailingText: nil,
                    isDisabled: installer.isBusy,
                    accessibilityElement: .uninstallButton,
                    action: uninstallOpenClaw
                )
            }

            if snapshot.showsQuitAction {
                actionButton(
                    title: model.quitButtonTitle,
                    systemImage: "power",
                    trailingText: "⌘Q",
                    isDisabled: false,
                    accessibilityElement: .quitButton
                ) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(height: 1)
    }

    private func statusRow(_ row: MenuPanelRowSnapshot) -> some View {
        Button {
            openApplicationManagement(section: applicationManagementSection(for: row.dimension))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(theme.primaryText)

                        Text(row.summary)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 10)

                    Text(row.statusLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.pillForeground(for: row.level))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.pillBackground(for: row.level))
                        .clipShape(Capsule())
                }

                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(theme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(theme.rowBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(theme.panelBorder.opacity(0.85), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        trailingText: String?,
        isDisabled: Bool,
        accessibilityElement: MenuContentElement,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(theme.actionIcon)
                    .frame(width: 14)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.primaryText)

                Spacer(minLength: 8)

                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(theme.tertiaryText)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.tertiaryText)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.rowBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(model.accessibilityIdentifier(for: accessibilityElement))
    }

    private func accessibilityElement(for dimension: OpenClawHealthDimension) -> MenuContentElement {
        switch dimension {
        case .provider:
            .providerRow
        case .gateway:
            .gatewayRow
        case .channel:
            .channelRow
        }
    }

    private var overallHealthLevel: OpenClawHealthLevel {
        installer.healthSnapshot?.overallLevel ?? .unknown
    }

    private var showsInitialRefreshIndicator: Bool {
        installer.isRefreshingStatus && installer.lastStatusRefreshDate == nil
    }

    private func applicationManagementSection(for dimension: OpenClawHealthDimension) -> ApplicationManagementSection {
        switch dimension {
        case .provider:
            .provider
        case .gateway:
            .gateway
        case .channel:
            .channels
        }
    }

    private var upgradeButtonTitle: String {
        if installer.isUpdating {
            return "升级中…"
        }

        if installer.isUpdateAvailable == false {
            return "已是最新版本"
        }

        if installer.isUpdateAvailable == true,
           let latestVersion = installer.latestVersion {
            return "升级到 OpenClaw \(latestVersion)"
        }

        return model.upgradeButtonTitle
    }

    private var isUpgradeActionDisabled: Bool {
        installer.isBusy || installer.isUpdateAvailable == false
    }

    private func installOpenClaw() {
        openWindow(id: ClawbarWindow.openClawInstallID)
        NSApp.activate(ignoringOtherApps: true)
        installer.startInstallIfNeeded()
    }

    private func upgradeOpenClaw() {
        openWindow(id: ClawbarWindow.openClawInstallID)
        NSApp.activate(ignoringOtherApps: true)
        installer.startUpdateIfNeeded()
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

    private func openApplicationManagement(section: ApplicationManagementSection) {
        applicationManagementRouter.show(section)
        openApplicationManagement()
    }
}
