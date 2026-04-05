import Foundation

enum OpenClawHealthLevel: String, Equatable, Sendable {
    case healthy
    case warning
    case critical
    case unknown
}

enum OpenClawHealthDimension: String, CaseIterable, Equatable, Sendable, Identifiable {
    case provider
    case gateway
    case channel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .provider:
            "Provider"
        case .gateway:
            "Gateway"
        case .channel:
            "Channel"
        }
    }
}

struct OpenClawHealthDimensionSnapshot: Equatable, Sendable, Identifiable {
    let dimension: OpenClawHealthDimension
    let level: OpenClawHealthLevel
    let statusLabel: String
    let summary: String
    let detail: String

    var id: OpenClawHealthDimension { dimension }

    var compactSummary: String {
        "\(dimension.title) \(statusLabel)"
    }
}

struct OpenClawHealthSnapshot: Equatable, Sendable {
    let runtimeVersion: String?
    let dimensions: [OpenClawHealthDimensionSnapshot]

    var overviewText: String {
        dimensions.map(\.compactSummary).joined(separator: " · ")
    }

    var runtimeText: String? {
        runtimeVersion.map { "OpenClaw \($0)" }
    }

    var overallLevel: OpenClawHealthLevel {
        if dimensions.contains(where: { $0.level == .critical }) {
            return .critical
        }
        if dimensions.contains(where: { $0.level == .warning }) {
            return .warning
        }
        if dimensions.allSatisfy({ $0.level == .healthy }) {
            return .healthy
        }
        return .unknown
    }

    static let placeholderInstalled = OpenClawHealthSnapshot(
        runtimeVersion: nil,
        dimensions: [
            OpenClawHealthDimensionSnapshot(
                dimension: .provider,
                level: .unknown,
                statusLabel: "等待刷新",
                summary: "正在读取默认模型和认证状态",
                detail: "Clawbar 下一次状态刷新会同步 Provider 健康信息。"
            ),
            OpenClawHealthDimensionSnapshot(
                dimension: .gateway,
                level: .unknown,
                statusLabel: "等待刷新",
                summary: "正在读取 Gateway 服务与可达性",
                detail: "Clawbar 下一次状态刷新会同步 Gateway 健康信息。"
            ),
            OpenClawHealthDimensionSnapshot(
                dimension: .channel,
                level: .unknown,
                statusLabel: "等待刷新",
                summary: "正在读取 Channel 摘要",
                detail: "Clawbar 下一次状态刷新会同步 Channel 健康信息。"
            ),
        ]
    )

    static let deterministicInstalled = OpenClawHealthSnapshot(
        runtimeVersion: "2026.4.2",
        dimensions: [
            OpenClawHealthDimensionSnapshot(
                dimension: .provider,
                level: .healthy,
                statusLabel: "已配置",
                summary: "OpenRouter / qwen/qwen3.6-plus:free",
                detail: "认证来源：env: OPENROUTER_API_KEY"
            ),
            OpenClawHealthDimensionSnapshot(
                dimension: .gateway,
                level: .healthy,
                statusLabel: "可达",
                summary: "后台服务运行中",
                detail: "Gateway 后台服务正在运行。"
            ),
            OpenClawHealthDimensionSnapshot(
                dimension: .channel,
                level: .healthy,
                statusLabel: "已就绪",
                summary: "openclaw-weixin / 已配置",
                detail: "openclaw-weixin: 已配置"
            ),
        ]
    )
}
