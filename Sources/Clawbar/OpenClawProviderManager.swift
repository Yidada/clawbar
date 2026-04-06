import Foundation

enum ProviderCustomCompatibility: String, CaseIterable, Identifiable, Sendable {
    case openAI = "openai"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            "OpenAI Compatible"
        case .anthropic:
            "Anthropic Compatible"
        }
    }

    var configAPI: String {
        switch self {
        case .openAI:
            "openai-completions"
        case .anthropic:
            "anthropic-messages"
        }
    }
}

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

enum OpenClawProviderSavePlanError: LocalizedError, Equatable {
    case missingBinary
    case missingCustomBaseURL
    case missingModel

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "未检测到 openclaw，请先安装。"
        case .missingCustomBaseURL:
            "Custom Provider 需要填写 Base URL。"
        case .missingModel:
            "请填写模型 ID，或选择带建议模型的 Provider。"
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

    @Published var selectedProvider: ProviderKind = .openAI
    @Published var customCompatibility: ProviderCustomCompatibility = .openAI
    @Published var draftBaseURL = ""
    @Published var draftModel = ""
    @Published var draftAPIKey = ""

    @Published private(set) var isRefreshing = false
    @Published private(set) var isSaving = false
    @Published private(set) var binaryPath: String?
    @Published private(set) var configPath: String?
    @Published private(set) var defaultModelRef: String?
    @Published private(set) var detectedAuthState: OpenClawProviderAuthState?
    @Published private(set) var hasExplicitAPIKeyOverride = false
    @Published private(set) var lastActionSummary = "等待写入"
    @Published private(set) var lastActionDetail = "保存后会调用 openclaw CLI 写入或修改 Provider 配置。"
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?

    private let environmentProvider: EnvironmentProvider
    private let runCommand: CommandRunner
    private var latestSnapshot: OpenClawProviderSnapshot?
    private var hasLoadedInitialState = false

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = OpenClawProviderManager.runCommand
    ) {
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
    }

    func refreshStatus(syncSelectionWithDefault: Bool = false) {
        guard !isRefreshing else { return }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        isRefreshing = true

        Task.detached(priority: .utility) {
            let binaryPath = Self.detectInstalledBinaryPath(environment: environment)
            let snapshot = binaryPath.flatMap {
                Self.loadStatusSnapshot(binaryPath: $0, environment: environment, runCommand: self.runCommand)
            }

            let shouldSyncSelection = await MainActor.run {
                syncSelectionWithDefault || !self.hasLoadedInitialState
            }

            let nextProvider = snapshot.flatMap { parsedSnapshot in
                shouldSyncSelection
                    ? (Self.providerKind(from: parsedSnapshot.defaultModelRef) ?? .openAI)
                    : nil
            }

            let targetProvider = await MainActor.run {
                nextProvider ?? self.selectedProvider
            }

            let explicitBaseURL = binaryPath.flatMap {
                Self.loadConfigValue(
                    binaryPath: $0,
                    environment: environment,
                    path: "models.providers.\(targetProvider.rawValue).baseUrl",
                    runCommand: self.runCommand
                )
            }
            let explicitAPIKeyExists = binaryPath.map {
                Self.configValueExists(
                    binaryPath: $0,
                    environment: environment,
                    path: "models.providers.\(targetProvider.rawValue).apiKey",
                    runCommand: self.runCommand
                )
            } ?? false
            let explicitAPI = binaryPath.flatMap {
                Self.loadConfigValue(
                    binaryPath: $0,
                    environment: environment,
                    path: "models.providers.\(targetProvider.rawValue).api",
                    runCommand: self.runCommand
                )
            }

            await MainActor.run {
                self.binaryPath = binaryPath.map(OpenClawInstaller.displayBinaryPath(_:))
                self.isRefreshing = false
                self.lastRefreshDate = Date()
                self.hasLoadedInitialState = true

                guard let snapshot else {
                    self.latestSnapshot = nil
                    self.configPath = nil
                    self.defaultModelRef = nil
                    self.detectedAuthState = nil
                    self.hasExplicitAPIKeyOverride = false
                    self.lastActionSummary = "未检测到 OpenClaw"
                    self.lastActionDetail = "请先安装 openclaw，然后再管理 Provider。"
                    self.lastCommandOutput = ""
                    self.draftBaseURL = ""
                    self.draftModel = targetProvider.suggestedModel
                    self.draftAPIKey = ""
                    return
                }

                self.latestSnapshot = snapshot
                self.configPath = snapshot.configPath
                self.defaultModelRef = snapshot.defaultModelRef
                if let nextProvider {
                    self.selectedProvider = nextProvider
                }
                self.detectedAuthState = snapshot.authStates[targetProvider.rawValue]
                self.hasExplicitAPIKeyOverride = explicitAPIKeyExists
                self.customCompatibility = Self.customCompatibility(
                    from: explicitAPI,
                    provider: targetProvider
                )
                self.draftBaseURL = explicitBaseURL ?? ""
                self.draftModel = Self.modelDraft(
                    for: targetProvider,
                    defaultModelRef: snapshot.defaultModelRef
                )
                self.draftAPIKey = ""
                self.lastActionSummary = "已同步 OpenClaw 配置"
                self.lastActionDetail = Self.authDetailText(
                    provider: targetProvider,
                    authState: snapshot.authStates[targetProvider.rawValue],
                    hasExplicitAPIKeyOverride: explicitAPIKeyExists
                )
            }
        }
    }

    func refreshSelectedProvider() {
        refreshStatus(syncSelectionWithDefault: false)
    }

    func saveCurrentProvider() {
        guard !isSaving else { return }
        guard let binaryPath = Self.detectInstalledBinaryPath(
            environment: OpenClawInstaller.installationEnvironment(base: environmentProvider())
        ) else {
            lastActionSummary = "未检测到 OpenClaw"
            lastActionDetail = OpenClawProviderSavePlanError.missingBinary.localizedDescription
            return
        }

        let savePlan: [OpenClawProviderCLIInvocation]

        do {
            savePlan = try Self.makeSavePlan(
                provider: selectedProvider,
                customCompatibility: customCompatibility,
                baseURL: draftBaseURL,
                model: draftModel,
                apiKey: draftAPIKey
            )
        } catch {
            lastActionSummary = "Provider 保存失败"
            lastActionDetail = error.localizedDescription
            return
        }

        let environment = OpenClawInstaller.installationEnvironment(base: environmentProvider())
        isSaving = true
        lastActionSummary = "正在写入 Provider..."
        lastActionDetail = "等待 openclaw CLI 完成写入。"
        lastCommandOutput = savePlan.map(Self.renderCommandLine(_:)).joined(separator: "\n")

        Task.detached(priority: .userInitiated) {
            var outputs: [String] = []

            for invocation in savePlan {
                let result = self.runCommand(binaryPath, invocation.arguments, environment, 30)
                outputs.append("\(Self.renderCommandLine(invocation))\n\(result.output.nonEmptyOr("(no output)"))")

                if result.timedOut || result.exitStatus != 0 {
                    await MainActor.run {
                        self.isSaving = false
                        self.lastActionSummary = "Provider 保存失败"
                        self.lastActionDetail = result.timedOut
                            ? "命令执行超时。"
                            : result.output.nonEmptyOr("命令返回了非零退出码 \(result.exitStatus)。")
                        self.lastCommandOutput = outputs.joined(separator: "\n\n")
                    }
                    return
                }
            }

            await MainActor.run {
                self.isSaving = false
                self.draftAPIKey = ""
                self.lastActionSummary = "Provider 已写入"
                self.lastActionDetail = "openclaw CLI 已完成写入，正在刷新当前状态。"
                self.lastCommandOutput = outputs.joined(separator: "\n\n")
                self.refreshStatus(syncSelectionWithDefault: true)
            }
        }
    }

    func applySuggestedValues() {
        if draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftBaseURL = selectedProvider.suggestedBaseURL
        }

        if draftModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draftModel = selectedProvider.suggestedModel
        }
    }

    func clearDrafts() {
        draftBaseURL = ""
        draftModel = ""
        draftAPIKey = ""
    }

    nonisolated static func makeSavePlan(
        provider: ProviderKind,
        customCompatibility: ProviderCustomCompatibility,
        baseURL: String,
        model: String,
        apiKey: String
    ) throws -> [OpenClawProviderCLIInvocation] {
        let trimmedBaseURL = baseURL.trimmedNonEmpty
        let trimmedModel = model.trimmedNonEmpty ?? provider.suggestedModel.trimmedNonEmpty
        let trimmedAPIKey = apiKey.trimmedNonEmpty

        guard let resolvedModel = trimmedModel else {
            throw OpenClawProviderSavePlanError.missingModel
        }

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

        var invocations: [OpenClawProviderCLIInvocation] = []

        switch provider {
        case .openAI:
            if let trimmedBaseURL {
                invocations.append(
                    customProviderInvocation(
                        baseFlags: baseFlags,
                        providerID: provider.rawValue,
                        baseURL: trimmedBaseURL,
                        modelID: resolvedModel,
                        compatibility: .openAI,
                        apiKey: trimmedAPIKey
                    )
                )
            } else if let trimmedAPIKey {
                invocations.append(
                    OpenClawProviderCLIInvocation(
                        arguments: baseFlags + [
                            "--auth-choice", "openai-api-key",
                            "--openai-api-key", trimmedAPIKey,
                        ],
                        redactedArguments: baseFlags + [
                            "--auth-choice", "openai-api-key",
                            "--openai-api-key", "<redacted>",
                        ]
                    )
                )
            }
        case .anthropic:
            if let trimmedBaseURL {
                invocations.append(
                    customProviderInvocation(
                        baseFlags: baseFlags,
                        providerID: provider.rawValue,
                        baseURL: trimmedBaseURL,
                        modelID: resolvedModel,
                        compatibility: .anthropic,
                        apiKey: trimmedAPIKey
                    )
                )
            } else if let trimmedAPIKey {
                invocations.append(
                    OpenClawProviderCLIInvocation(
                        arguments: baseFlags + [
                            "--auth-choice", "anthropic-api-key",
                            "--anthropic-api-key", trimmedAPIKey,
                        ],
                        redactedArguments: baseFlags + [
                            "--auth-choice", "anthropic-api-key",
                            "--anthropic-api-key", "<redacted>",
                        ]
                    )
                )
            }
        case .openRouter:
            if let trimmedBaseURL {
                invocations.append(
                    customProviderInvocation(
                        baseFlags: baseFlags,
                        providerID: provider.rawValue,
                        baseURL: trimmedBaseURL,
                        modelID: resolvedModel,
                        compatibility: .openAI,
                        apiKey: trimmedAPIKey
                    )
                )
            } else if let trimmedAPIKey {
                invocations.append(
                    OpenClawProviderCLIInvocation(
                        arguments: baseFlags + [
                            "--auth-choice", "openrouter-api-key",
                            "--openrouter-api-key", trimmedAPIKey,
                        ],
                        redactedArguments: baseFlags + [
                            "--auth-choice", "openrouter-api-key",
                            "--openrouter-api-key", "<redacted>",
                        ]
                    )
                )
            }
        case .liteLLM:
            if let trimmedBaseURL {
                invocations.append(
                    customProviderInvocation(
                        baseFlags: baseFlags,
                        providerID: provider.rawValue,
                        baseURL: trimmedBaseURL,
                        modelID: resolvedModel,
                        compatibility: .openAI,
                        apiKey: trimmedAPIKey
                    )
                )
            } else if let trimmedAPIKey {
                invocations.append(
                    OpenClawProviderCLIInvocation(
                        arguments: baseFlags + [
                            "--auth-choice", "litellm-api-key",
                            "--litellm-api-key", trimmedAPIKey,
                        ],
                        redactedArguments: baseFlags + [
                            "--auth-choice", "litellm-api-key",
                            "--litellm-api-key", "<redacted>",
                        ]
                    )
                )
            }
        case .ollama:
            invocations.append(
                ollamaInvocation(
                    baseFlags: baseFlags,
                    baseURL: trimmedBaseURL ?? provider.suggestedBaseURL,
                    modelID: resolvedModel,
                    apiKey: trimmedAPIKey
                )
            )
        case .custom:
            guard let trimmedBaseURL else {
                throw OpenClawProviderSavePlanError.missingCustomBaseURL
            }
            invocations.append(
                customProviderInvocation(
                    baseFlags: baseFlags,
                    providerID: provider.rawValue,
                    baseURL: trimmedBaseURL,
                    modelID: resolvedModel,
                    compatibility: customCompatibility,
                    apiKey: trimmedAPIKey
                )
            )
        }

        invocations.append(
            OpenClawProviderCLIInvocation(
                arguments: [
                    "config",
                    "set",
                    "agents.defaults.model.primary",
                    "\(provider.rawValue)/\(resolvedModel)",
                ],
                redactedArguments: [
                    "config",
                    "set",
                    "agents.defaults.model.primary",
                    "\(provider.rawValue)/\(resolvedModel)",
                ]
            )
        )

        return invocations
    }

    private nonisolated static func customProviderInvocation(
        baseFlags: [String],
        providerID: String,
        baseURL: String,
        modelID: String,
        compatibility: ProviderCustomCompatibility,
        apiKey: String?
    ) -> OpenClawProviderCLIInvocation {
        var arguments = baseFlags + [
            "--auth-choice", "custom-api-key",
            "--custom-provider-id", providerID,
            "--custom-base-url", baseURL,
            "--custom-model-id", modelID,
            "--custom-compatibility", compatibility.rawValue,
        ]
        var redactedArguments = arguments

        if let apiKey {
            arguments += ["--custom-api-key", apiKey]
            redactedArguments += ["--custom-api-key", "<redacted>"]
        }

        return OpenClawProviderCLIInvocation(
            arguments: arguments,
            redactedArguments: redactedArguments
        )
    }

    private nonisolated static func ollamaInvocation(
        baseFlags: [String],
        baseURL: String,
        modelID: String,
        apiKey: String?
    ) -> OpenClawProviderCLIInvocation {
        var arguments = baseFlags + [
            "--auth-choice", "ollama",
            "--custom-base-url", baseURL,
            "--custom-model-id", modelID,
        ]
        var redactedArguments = arguments

        if let apiKey {
            arguments += ["--custom-api-key", apiKey]
            redactedArguments += ["--custom-api-key", "<redacted>"]
        }

        return OpenClawProviderCLIInvocation(
            arguments: arguments,
            redactedArguments: redactedArguments
        )
    }

    private nonisolated static func modelDraft(
        for provider: ProviderKind,
        defaultModelRef: String?
    ) -> String {
        guard
            let defaultModelRef,
            defaultModelRef.hasPrefix("\(provider.rawValue)/")
        else {
            return provider.suggestedModel
        }

        return String(defaultModelRef.dropFirst(provider.rawValue.count + 1))
    }

    private nonisolated static func providerKind(from defaultModelRef: String?) -> ProviderKind? {
        guard let defaultModelRef else { return nil }
        return ProviderKind.allCases.first { defaultModelRef.hasPrefix("\($0.rawValue)/") }
    }

    private nonisolated static func customCompatibility(
        from api: String?,
        provider: ProviderKind
    ) -> ProviderCustomCompatibility {
        if provider == .custom || provider == .anthropic {
            return api == ProviderCustomCompatibility.anthropic.configAPI ? .anthropic : .openAI
        }

        return .openAI
    }

    private nonisolated static func authDetailText(
        provider: ProviderKind,
        authState: OpenClawProviderAuthState?,
        hasExplicitAPIKeyOverride: Bool
    ) -> String {
        if hasExplicitAPIKeyOverride {
            return "\(provider.displayName) 的 API Key 已明确写入 openclaw 配置。"
        }

        guard let authState else {
            return "当前还没有检测到 \(provider.displayName) 的认证来源。"
        }

        if authState.isConfigured {
            let source = authState.source?.trimmedNonEmpty ?? authState.detail
            return "\(provider.displayName) 当前认证来源：\(source)。"
        }

        return "当前还没有检测到 \(provider.displayName) 的认证来源。"
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

    private nonisolated static func loadConfigValue(
        binaryPath: String,
        environment: [String: String],
        path: String,
        runCommand: CommandRunner
    ) -> String? {
        let result = runCommand(binaryPath, ["config", "get", path], environment, 5)
        guard !result.timedOut, result.exitStatus == 0 else { return nil }
        return result.output.trimmedNonEmpty
    }

    nonisolated static func renderCommandLine(_ invocation: OpenClawProviderCLIInvocation) -> String {
        let rendered = invocation.redactedArguments
            .map(Self.shellEscape(_:))
            .joined(separator: " ")
        return "$ openclaw \(rendered)"
    }

    private nonisolated static func shellEscape(_ text: String) -> String {
        guard !text.isEmpty else { return "''" }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._/:")
        if text.unicodeScalars.allSatisfy(allowed.contains) {
            return text
        }

        return "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private nonisolated static func runCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> OpenClawProviderCommandResult {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return OpenClawProviderCommandResult(
                output: error.localizedDescription,
                exitStatus: 1,
                timedOut: false
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false

        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            timedOut = true
            process.terminate()
            process.waitUntilExit()
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return OpenClawProviderCommandResult(
            output: sanitizeProviderCommandOutput(data),
            exitStatus: process.terminationStatus,
            timedOut: timedOut
        )
    }
}

private func sanitizeProviderCommandOutput(_ data: Data) -> String {
    let raw = String(decoding: data, as: UTF8.self)
    let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return raw
    }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
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
