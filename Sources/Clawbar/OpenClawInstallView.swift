import SwiftUI

struct OpenClawInstallView: View {
    @ObservedObject var installer: OpenClawInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                if installer.isInstalling {
                    ProgressView()
                        .controlSize(.small)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(installer.statusText)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(installer.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Text("安装日志")
                    .font(.headline)

                Spacer()

                Text(installer.lastLogURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    Text(installer.logText.isEmpty ? "等待安装输出..." : installer.logText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                        .id("log-bottom")
                }
                .background(.quaternary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: installer.logText) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
            }

            Text("说明：官方安装脚本没有提供稳定的百分比进度，所以这里展示实时输出和当前状态。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 760, height: 520)
    }
}
