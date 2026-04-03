import AppKit
import SwiftUI
import ClawbarKit

struct MenuContentView: View {
    let model: MenuContentModel
    @ObservedObject private var installer = OpenClawInstaller.shared

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
                Divider()
            } else {
                Button(installer.isInstalling ? "安装中..." : model.installButtonTitle) {
                    installOpenClaw()
                }
                .disabled(installer.isInstalling)
                .accessibilityIdentifier(model.accessibilityIdentifier(for: .installButton))
            }

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
                    .fill(installer.isRefreshingStatus ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)

                Text("OpenClaw")
                    .font(.subheadline)
                    .fontWeight(.semibold)

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
            }

            Text(installer.detailText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let statusExcerpt = installer.statusExcerpt {
                Text(statusExcerpt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func installOpenClaw() {
        OpenClawInstallWindowPresenter.shared.showWindow(installer: installer)
        installer.startInstallIfNeeded()
    }
}
