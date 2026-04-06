import Foundation
import ClawbarKit

enum MenuPanelState: Equatable {
    case loading
    case installed
    case missing
}

struct MenuPanelRowSnapshot: Equatable, Identifiable {
    let dimension: OpenClawHealthDimension
    let level: OpenClawHealthLevel
    let statusLabel: String
    let summary: String
    let detail: String?

    var id: OpenClawHealthDimension { dimension }
    var title: String { dimension.title }
}

struct MenuPanelSnapshot: Equatable {
    let state: MenuPanelState
    let title: String
    let subtitle: String
    let metadata: String?
    let binaryPath: String?
    let rows: [MenuPanelRowSnapshot]
    let showsInstallAction: Bool
    let showsTUIDebugAction: Bool
    let showsUninstallAction: Bool
    let showsSettingsAction: Bool
    let showsQuitAction: Bool
}

enum MenuPanelSnapshotFactory {
    static func make(
        model: MenuContentModel,
        isInstalled: Bool,
        isBusy: Bool,
        isRefreshingStatus: Bool,
        lastStatusRefreshDate: Date?,
        statusText: String,
        detailText: String,
        installedBinaryPath: String?,
        statusExcerpt: String?,
        healthSnapshot: OpenClawHealthSnapshot?
    ) -> MenuPanelSnapshot {
        if shouldShowLoadingState(
            isInstalled: isInstalled,
            isBusy: isBusy,
            isRefreshingStatus: isRefreshingStatus,
            lastStatusRefreshDate: lastStatusRefreshDate,
            installedBinaryPath: installedBinaryPath,
            statusExcerpt: statusExcerpt,
            healthSnapshot: healthSnapshot
        ) {
            return MenuPanelSnapshot(
                state: .loading,
                title: model.installedTitle,
                subtitle: model.loadingSubtitle,
                metadata: nil,
                binaryPath: nil,
                rows: [],
                showsInstallAction: false,
                showsTUIDebugAction: false,
                showsUninstallAction: false,
                showsSettingsAction: true,
                showsQuitAction: true
            )
        }

        if isInstalled {
            return MenuPanelSnapshot(
                state: .installed,
                title: model.installedTitle,
                subtitle: primaryInstalledSubtitle(detailText: detailText, fallback: statusText),
                metadata: installedMetadata(
                    statusExcerpt: statusExcerpt,
                    isRefreshingStatus: isRefreshingStatus,
                    refreshingStatusLabel: model.refreshingStatusLabel
                ),
                binaryPath: trimmedNonEmpty(installedBinaryPath),
                rows: (healthSnapshot?.dimensions ?? []).map(rowSnapshot),
                showsInstallAction: false,
                showsTUIDebugAction: true,
                showsUninstallAction: true,
                showsSettingsAction: true,
                showsQuitAction: true
            )
        }

        return MenuPanelSnapshot(
            state: .missing,
            title: model.missingTitle,
            subtitle: isBusy ? statusText : model.missingSubtitle,
            metadata: isBusy ? trimmedNonEmpty(detailText) : nil,
            binaryPath: nil,
            rows: [],
            showsInstallAction: true,
            showsTUIDebugAction: false,
            showsUninstallAction: false,
            showsSettingsAction: true,
            showsQuitAction: true
        )
    }

    private static func shouldShowLoadingState(
        isInstalled: Bool,
        isBusy: Bool,
        isRefreshingStatus: Bool,
        lastStatusRefreshDate: Date?,
        installedBinaryPath: String?,
        statusExcerpt: String?,
        healthSnapshot: OpenClawHealthSnapshot?
    ) -> Bool {
        guard !isInstalled, !isBusy else {
            return false
        }

        if isRefreshingStatus && lastStatusRefreshDate == nil {
            return true
        }

        return lastStatusRefreshDate == nil
            && trimmedNonEmpty(installedBinaryPath) == nil
            && trimmedNonEmpty(statusExcerpt) == nil
            && healthSnapshot == nil
    }

    private static func primaryInstalledSubtitle(detailText: String, fallback: String) -> String {
        trimmedNonEmpty(detailText) ?? fallback
    }

    private static func installedMetadata(
        statusExcerpt: String?,
        isRefreshingStatus: Bool,
        refreshingStatusLabel: String
    ) -> String? {
        if let statusExcerpt = trimmedNonEmpty(statusExcerpt) {
            return statusExcerpt
        }
        return isRefreshingStatus ? refreshingStatusLabel : nil
    }

    private static func rowSnapshot(_ dimension: OpenClawHealthDimensionSnapshot) -> MenuPanelRowSnapshot {
        MenuPanelRowSnapshot(
            dimension: dimension.dimension,
            level: dimension.level,
            statusLabel: dimension.statusLabel,
            summary: dimension.summary,
            detail: dimension.level == .healthy ? nil : trimmedNonEmpty(dimension.detail)
        )
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
