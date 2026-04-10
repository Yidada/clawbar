import Foundation

struct OpenClawProviderCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

struct OpenClawProviderCLIInvocation: Equatable, Sendable {
    let arguments: [String]
    let redactedArguments: [String]
}

struct OpenClawProviderAuthState: Equatable, Sendable {
    let kind: String
    let detail: String
    let source: String?

    var isConfigured: Bool {
        kind != "missing"
    }
}

struct OpenClawProviderSnapshot: Equatable, Sendable {
    let binaryPath: String
    let configPath: String?
    let defaultModelRef: String?
    let authStates: [String: OpenClawProviderAuthState]
}

enum OpenClawBindingState: Equatable, Sendable {
    case openClawMissing
    case waitingForOllama
    case applying
    case ready
    case drift(currentModelRef: String?)
    case needsConfiguration
    case failed(detail: String)

    var title: String {
        switch self {
        case .openClawMissing:
            "OpenClaw 未安装"
        case .waitingForOllama:
            "等待内置 Ollama"
        case .applying:
            "正在恢复 Gemma 4 配置"
        case .ready:
            "OpenClaw 已绑定 Gemma 4"
        case .drift:
            "当前配置已偏离受支持版本"
        case .needsConfiguration:
            "OpenClaw 尚未绑定 Gemma 4"
        case .failed:
            "恢复 Gemma 4 配置失败"
        }
    }

    var statusLabel: String {
        switch self {
        case .openClawMissing:
            "未安装"
        case .waitingForOllama:
            "等待中"
        case .applying:
            "写入中"
        case .ready:
            "已绑定"
        case .drift:
            "已漂移"
        case .needsConfiguration:
            "待配置"
        case .failed:
            "失败"
        }
    }
}

enum OpenClawProviderSavePlanError: LocalizedError, Equatable {
    case missingBinary

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "未检测到 openclaw，请先安装。"
        }
    }
}

@MainActor
final class OpenClawProviderManager: ObservableObject {
    static let shared = OpenClawProviderManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> OpenClawProviderCommandResult

    nonisolated static let supportedProviderID = "ollama"
    nonisolated static let supportedModelID = EmbeddedOllamaManager.supportedModelID
    nonisolated static let supportedModelReference = "\(supportedProviderID)/\(supportedModelID)"
    nonisolated static let supportedBaseURL = EmbeddedOllamaManager.defaultBaseURL.absoluteString
    nonisolated static let legacyProviderConfigPaths = [
        "models.providers.openai",
        "models.providers.openai-codex",
        "models.providers.anthropic",
        "models.providers.openrouter",
        "models.providers.litellm",
        "models.providers.custom",
    ]

    @Published private(set) var isRefreshing = false
    @Published private(set) var isSaving = false
    @Published private(set) var binaryPath: String?
    @Published private(set) var configPath: String?
    @Published private(set) var defaultModelRef: String?
    @Published private(set) var detectedAuthState: OpenClawProviderAuthState?
    @Published private(set) var bindingState: OpenClawBindingState = .openClawMissing
    @Published private(set) var lastActionSummary = "等待写入"
    @Published private(set) var lastActionDetail = "Clawbar 会把 OpenClaw 固定到 ollama/gemma4。"
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private var latestSnapshot: OpenClawProviderSnapshot?
    private var bootstrapTask: Task<Void, Never>?

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = OpenClawProviderManager.runCommand
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
    }

    var activeAuthState: OpenClawProviderAuthState? {
        detectedAuthState
    }

    var currentModelLabel: String {
        defaultModelRef ?? "未设置"
    }

    var configSummary: String {
        switch bindingState {
        case .ready:
            return "当前默认模型已固定到 \(Self.supportedModelReference)。"
        case let .drift(currentModelRef):
            return "当前默认模型是 \(currentModelRef ?? "未设置")。Clawbar 只支持 \(Self.supportedModelReference)。"
        case .needsConfiguration:
            return "当前还没有把 OpenClaw 绑定到 \(Self.supportedModelReference)。"
        case .openClawMissing:
            return "请先安装 OpenClaw。"
        case .waitingForOllama:
            return "需要先准备内置 Ollama runtime 和 gemma4。"
        case .applying:
            return "Clawbar 正在恢复受支持配置。"
        case let .failed(detail):
            return detail
        }
    }

    func refreshStatus() {
        guard !isRefreshing else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        isRefreshing = true

        Task.detached(priority: .utility) {
            let binaryPath = Self.detectInstalledBinaryPath(environment: environment)
            let snapshot = binaryPath.flatMap {
                Self.loadStatusSnapshot(binaryPath: $0, environment: environment, runCommand: self.runCommand)
            }

            await MainActor.run {
                self.isRefreshing = false
                self.binaryPath = binaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.latestSnapshot = snapshot
                self.configPath = snapshot?.configPath
                self.defaultModelRef = snapshot?.defaultModelRef
                self.detectedAuthState = snapshot?.authStates[Self.supportedProviderID]
                self.bindingState = Self.resolveBindingState(snapshot: snapshot)
                self.lastRefreshDate = Date()

                if snapshot == nil {
                    self.lastActionSummary = "未检测到 OpenClaw"
                    self.lastActionDetail = "请先安装 openclaw，然后再恢复 Gemma 4 配置。"
                } else {
                    self.lastActionSummary = "已同步 OpenClaw 配置"
                    self.lastActionDetail = self.configSummary
                }
            }
        }
    }

    func restoreGemma4Configuration() {
        startBootstrap(force: true, allowInstall: true, reason: "manual.restore")
    }

    func bootstrapIfPossible(reason: String) {
        startBootstrap(force: false, allowInstall: false, reason: reason)
    }

    private func startBootstrap(force: Bool, allowInstall: Bool, reason: String) {
        guard bootstrapTask == nil else { return }

        bootstrapTask = Task { [weak self] in
            guard let self else { return }
            await self.applySupportedConfiguration(
                force: force,
                allowInstall: allowInstall,
                reason: reason
            )
            await MainActor.run {
                self.bootstrapTask = nil
            }
        }
    }

    private func applySupportedConfiguration(
        force: Bool,
        allowInstall: Bool,
        reason: String
    ) async {
        let runtimeReady = await EmbeddedOllamaManager.shared.ensureRuntimeAndModelReady(
            forceRefresh: force,
            allowInstall: allowInstall
        )
        guard runtimeReady else {
            await MainActor.run {
                self.bindingState = .waitingForOllama
                self.lastActionSummary = "等待内置 Ollama"
                self.lastActionDetail = EmbeddedOllamaManager.shared.lastActionDetail
                self.lastCommandOutput = EmbeddedOllamaManager.shared.lastCommandOutput
            }
            refreshStatus()
            return
        }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        guard let binaryPath = Self.detectInstalledBinaryPath(environment: environment) else {
            await MainActor.run {
                self.bindingState = .openClawMissing
                self.binaryPath = nil
                self.lastActionSummary = "未检测到 OpenClaw"
                self.lastActionDetail = OpenClawProviderSavePlanError.missingBinary.localizedDescription
            }
            return
        }

        let snapshot = Self.loadStatusSnapshot(binaryPath: binaryPath, environment: environment, runCommand: runCommand)
        let existingLegacyProviderPaths = Self.legacyProviderConfigPaths.filter {
            Self.configValueExists(
                binaryPath: binaryPath,
                environment: environment,
                path: $0,
                runCommand: runCommand
            )
        }

        if !force,
           snapshot?.defaultModelRef == Self.supportedModelReference,
           snapshot?.authStates[Self.supportedProviderID]?.isConfigured == true,
           existingLegacyProviderPaths.isEmpty {
            await MainActor.run {
                self.latestSnapshot = snapshot
                self.binaryPath = OpenClawInstaller.displayBinaryPath(binaryPath)
                self.configPath = snapshot?.configPath
                self.defaultModelRef = snapshot?.defaultModelRef
                self.detectedAuthState = snapshot?.authStates[Self.supportedProviderID]
                self.bindingState = .ready
                self.lastActionSummary = "OpenClaw 已绑定 Gemma 4"
                self.lastActionDetail = "启动时已检测到受支持配置，无需再次写入。"
            }
            return
        }

        let savePlan = Self.makeSavePlan(existingLegacyProviderPaths: existingLegacyProviderPaths)

        await MainActor.run {
            self.isSaving = true
            self.bindingState = .applying
            self.binaryPath = OpenClawInstaller.displayBinaryPath(binaryPath)
            self.lastActionSummary = "正在恢复 Gemma 4 配置..."
            self.lastActionDetail = "触发来源：\(reason)。"
            self.lastCommandOutput = savePlan.map(Self.renderCommandLine(_:)).joined(separator: "\n")
        }

        var outputs: [String] = []

        for invocation in savePlan {
            let result = runCommand(binaryPath, invocation.arguments, environment, 60)
            outputs.append("\(Self.renderCommandLine(invocation))\n\(result.output.nonEmptyOr("(no output)"))")

            if result.timedOut || result.exitStatus != 0 {
                await MainActor.run {
                    self.isSaving = false
                    self.bindingState = .failed(detail: result.output.nonEmptyOr("命令返回了非零退出码 \(result.exitStatus)。"))
                    self.lastActionSummary = "恢复 Gemma 4 配置失败"
                    self.lastActionDetail = result.timedOut
                        ? "命令执行超时。"
                        : result.output.nonEmptyOr("命令返回了非零退出码 \(result.exitStatus)。")
                    self.lastCommandOutput = outputs.joined(separator: "\n\n")
                }
                refreshStatus()
                return
            }
        }

        await MainActor.run {
            self.isSaving = false
            self.lastActionSummary = "OpenClaw 已绑定 Gemma 4"
            self.lastActionDetail = "Clawbar 已恢复受支持配置。"
            self.lastCommandOutput = outputs.joined(separator: "\n\n")
        }
        refreshStatus()
    }

    nonisolated static func makeSavePlan(
        existingLegacyProviderPaths: [String] = []
    ) -> [OpenClawProviderCLIInvocation] {
        let baseFlags = [
            "onboard",
            "--non-interactive",
            "--accept-risk",
            "--skip-daemon",
            "--skip-channels",
            "--skip-skills",
            "--skip-search",
            "--skip-health",
            "--skip-ui",
        ]

        var plan: [OpenClawProviderCLIInvocation] = [
            OpenClawProviderCLIInvocation(
                arguments: baseFlags + [
                    "--auth-choice", "ollama",
                    "--custom-base-url", supportedBaseURL,
                    "--custom-model-id", supportedModelID,
                ],
                redactedArguments: baseFlags + [
                    "--auth-choice", "ollama",
                    "--custom-base-url", supportedBaseURL,
                    "--custom-model-id", supportedModelID,
                ]
            ),
            OpenClawProviderCLIInvocation(
                arguments: [
                    "config",
                    "set",
                    "agents.defaults.model.primary",
                    supportedModelReference,
                ],
                redactedArguments: [
                    "config",
                    "set",
                    "agents.defaults.model.primary",
                    supportedModelReference,
                ]
            ),
        ]

        for path in existingLegacyProviderPaths {
            plan.append(
                OpenClawProviderCLIInvocation(
                    arguments: ["config", "unset", path],
                    redactedArguments: ["config", "unset", path]
                )
            )
        }

        return plan
    }

    private nonisolated static func resolveBindingState(
        snapshot: OpenClawProviderSnapshot?
    ) -> OpenClawBindingState {
        guard let snapshot else {
            return .openClawMissing
        }

        let currentModelRef = trimmedNonEmpty(snapshot.defaultModelRef)
        let authConfigured = snapshot.authStates[supportedProviderID]?.isConfigured == true

        if currentModelRef == supportedModelReference, authConfigured {
            return .ready
        }

        if let currentModelRef, currentModelRef != supportedModelReference {
            return .drift(currentModelRef: currentModelRef)
        }

        return .needsConfiguration
    }

    private nonisolated static func detectInstalledBinaryPath(
        environment: [String: String]
    ) -> String? {
        let result = Self.runCommand(
            executablePath: "/usr/bin/which",
            arguments: ["openclaw"],
            environment: environment,
            timeout: 3
        )
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return result.output.trimmedNonEmpty
    }

    private nonisolated static func loadStatusSnapshot(
        binaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> OpenClawProviderSnapshot? {
        let result = runCommand(binaryPath, ["models", "status", "--json"], environment, 8)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return parseStatusSnapshot(result.output, binaryPath: binaryPath)
    }

    nonisolated static func parseStatusSnapshot(
        _ output: String,
        binaryPath: String
    ) -> OpenClawProviderSnapshot? {
        let jsonString = ChannelCommandSupport.extractTrailingJSONObjectString(from: output) ?? output
        guard
            let data = jsonString.data(using: .utf8),
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }

        let configPath = (payload["configPath"] as? String)?.trimmedNonEmpty
        let defaultModelRef = (payload["defaultModel"] as? String)?.trimmedNonEmpty
        let authPayload = (payload["auth"] as? [String: Any])?["providers"] as? [[String: Any]] ?? []
        var authStates: [String: OpenClawProviderAuthState] = [:]

        for providerPayload in authPayload {
            guard let providerID = (providerPayload["provider"] as? String)?.trimmedNonEmpty else {
                continue
            }

            let effective = providerPayload["effective"] as? [String: Any]
            let env = providerPayload["env"] as? [String: Any]
            let kind = (effective?["kind"] as? String)?.trimmedNonEmpty ?? "missing"
            let detail = (effective?["detail"] as? String)?.trimmedNonEmpty ?? "missing"
            let source = (env?["source"] as? String)?.trimmedNonEmpty

            authStates[providerID] = OpenClawProviderAuthState(
                kind: kind,
                detail: detail,
                source: source
            )
        }

        return OpenClawProviderSnapshot(
            binaryPath: binaryPath,
            configPath: configPath,
            defaultModelRef: defaultModelRef,
            authStates: authStates
        )
    }

    private nonisolated static func configValueExists(
        binaryPath: String,
        environment: [String: String],
        path: String,
        runCommand: CommandRunner
    ) -> Bool {
        let result = runCommand(binaryPath, ["config", "get", path], environment, 5)
        return !result.timedOut && result.exitStatus == 0 && result.output.trimmedNonEmpty != nil
    }

    nonisolated static func renderCommandLine(_ invocation: OpenClawProviderCLIInvocation) -> String {
        let rendered = invocation.redactedArguments
            .map(Self.shellEscape)
            .joined(separator: " ")
        return "$ openclaw \(rendered)"
    }

    private nonisolated static func shellEscape(_ value: String) -> String {
        if value.rangeOfCharacter(from: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'`$"))) == nil {
            return value
        }

        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private nonisolated static func runCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> OpenClawProviderCommandResult {
        let result = ChannelCommandSupport.runCommand(
            executablePath,
            arguments,
            environment,
            timeout
        )
        return OpenClawProviderCommandResult(
            output: result.output,
            exitStatus: result.exitStatus,
            timedOut: result.timedOut
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func nonEmptyOr(_ fallback: String) -> String {
        trimmedNonEmpty ?? fallback
    }
}
