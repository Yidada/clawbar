import Foundation

struct HermesProviderCLIInvocation: Equatable, Sendable {
    let arguments: [String]
    let redactedArguments: [String]
}

enum HermesProviderSavePlanError: LocalizedError, Equatable {
    case missingBinary
    case missingModel
    case missingCustomBaseURL
    case missingOllamaBaseURL
    case unsupportedProvider(ProviderKind)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "未检测到 hermes，请先安装 Hermes Agent。"
        case .missingModel:
            "请填写模型 ID（model）。"
        case .missingCustomBaseURL:
            "Custom Provider 需要填写 Base URL。"
        case .missingOllamaBaseURL:
            "Ollama Provider 需要填写 Base URL。"
        case let .unsupportedProvider(provider):
            "Hermes 暂不支持 Provider：\(provider.displayName)。"
        }
    }
}

@MainActor
final class HermesProviderManager: ObservableObject {
    static let shared = HermesProviderManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias CommandRunner = ChannelCommandSupport.CommandRunner

    nonisolated static let supportedProviders: [ProviderKind] = [
        .openAI,
        .anthropic,
        .openRouter,
        .ollama,
        .custom,
    ]

    @Published var selectedProvider: ProviderKind = .openAI
    @Published var customCompatibility: ProviderCustomCompatibility = .openAI
    @Published var draftBaseURL = ""
    @Published var draftModel = ""
    @Published var draftAPIKey = ""

    @Published private(set) var isSaving = false
    @Published private(set) var lastActionSummary = "等待写入"
    @Published private(set) var lastActionDetail = "保存后会调用 hermes config set 写入 ~/.hermes/config.yaml 与 .env。"
    @Published private(set) var lastInvocations: [HermesProviderCLIInvocation] = []
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastError: String?

    private let installer: HermesInstaller
    private let runCommand: CommandRunner
    private let environmentProvider: EnvironmentProvider

    init(
        installer: HermesInstaller = .shared,
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        runCommand: @escaping CommandRunner = ChannelCommandSupport.runCommand
    ) {
        self.installer = installer
        self.environmentProvider = environmentProvider
        self.runCommand = runCommand
    }

    func save() async {
        guard !isSaving else { return }
        guard let binaryPath = installer.hermesBinaryPath else {
            lastError = HermesProviderSavePlanError.missingBinary.errorDescription
            lastActionSummary = "未保存"
            lastActionDetail = lastError ?? ""
            return
        }

        let plan: [HermesProviderCLIInvocation]
        do {
            plan = try Self.makeSavePlan(
                provider: selectedProvider,
                customCompatibility: customCompatibility,
                baseURL: draftBaseURL,
                model: draftModel,
                apiKey: draftAPIKey
            )
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            lastActionSummary = "未保存"
            lastActionDetail = lastError ?? ""
            return
        }

        isSaving = true
        defer { isSaving = false }
        lastError = nil
        lastInvocations = plan
        lastCommandOutput = ""

        let env = ChannelCommandSupport.commandEnvironment(base: environmentProvider())
        var aggregatedOutput = ""
        let runner = runCommand

        for invocation in plan {
            let result = await Task.detached(priority: .utility) { @Sendable in
                runner(binaryPath, invocation.arguments, env, 30)
            }.value
            aggregatedOutput += "$ hermes \(invocation.redactedArguments.joined(separator: " "))\n"
            aggregatedOutput += result.output
            if !aggregatedOutput.hasSuffix("\n") { aggregatedOutput += "\n" }

            if result.timedOut {
                lastError = "hermes \(invocation.redactedArguments.first ?? "config") 超时。"
                lastActionSummary = "保存失败"
                lastActionDetail = lastError ?? ""
                lastCommandOutput = aggregatedOutput
                return
            }
            if result.exitStatus != 0 {
                lastError = "hermes \(invocation.redactedArguments.joined(separator: " ")) 失败（退出码 \(result.exitStatus)）。"
                lastActionSummary = "保存失败"
                lastActionDetail = lastError ?? ""
                lastCommandOutput = aggregatedOutput
                return
            }
        }

        lastCommandOutput = aggregatedOutput
        lastActionSummary = "已保存到 ~/.hermes/"
        lastActionDetail = "默认模型 \(draftModel.trimmedNonEmpty ?? "—") · provider \(selectedProvider.rawValue)"
        await installer.refreshStatus(force: true)
    }

    nonisolated static func makeSavePlan(
        provider: ProviderKind,
        customCompatibility: ProviderCustomCompatibility,
        baseURL: String,
        model: String,
        apiKey: String
    ) throws -> [HermesProviderCLIInvocation] {
        guard supportedProviders.contains(provider) else {
            throw HermesProviderSavePlanError.unsupportedProvider(provider)
        }

        let trimmedModel = model.trimmedNonEmpty
        guard let resolvedModel = trimmedModel else {
            throw HermesProviderSavePlanError.missingModel
        }

        let trimmedBaseURL = baseURL.trimmedNonEmpty
        let trimmedAPIKey = apiKey.trimmedNonEmpty

        var invocations: [HermesProviderCLIInvocation] = []

        let providerConfigKey = providerConfigValue(for: provider, compatibility: customCompatibility)

        invocations.append(plainConfigSet(key: "model", value: resolvedModel))
        invocations.append(plainConfigSet(key: "provider", value: providerConfigKey))

        switch provider {
        case .openAI:
            if let key = trimmedAPIKey {
                invocations.append(secretConfigSet(key: "OPENAI_API_KEY", value: key))
            }
            if let url = trimmedBaseURL {
                invocations.append(plainConfigSet(key: "OPENAI_BASE_URL", value: url))
            }
        case .anthropic:
            if let key = trimmedAPIKey {
                invocations.append(secretConfigSet(key: "ANTHROPIC_API_KEY", value: key))
            }
            if let url = trimmedBaseURL {
                invocations.append(plainConfigSet(key: "ANTHROPIC_BASE_URL", value: url))
            }
        case .openRouter:
            if let key = trimmedAPIKey {
                invocations.append(secretConfigSet(key: "OPENROUTER_API_KEY", value: key))
            }
            if let url = trimmedBaseURL {
                invocations.append(plainConfigSet(key: "OPENROUTER_BASE_URL", value: url))
            }
        case .ollama:
            guard let url = trimmedBaseURL else {
                throw HermesProviderSavePlanError.missingOllamaBaseURL
            }
            invocations.append(plainConfigSet(key: "OLLAMA_BASE_URL", value: url))
            if let key = trimmedAPIKey {
                invocations.append(secretConfigSet(key: "OLLAMA_API_KEY", value: key))
            }
        case .custom:
            guard let url = trimmedBaseURL else {
                throw HermesProviderSavePlanError.missingCustomBaseURL
            }
            let prefix = customConfigPrefix(for: customCompatibility)
            invocations.append(plainConfigSet(key: "\(prefix)_BASE_URL", value: url))
            if let key = trimmedAPIKey {
                invocations.append(secretConfigSet(key: "\(prefix)_API_KEY", value: key))
            }
        case .openAICodex, .liteLLM:
            throw HermesProviderSavePlanError.unsupportedProvider(provider)
        }

        return invocations
    }

    nonisolated private static func plainConfigSet(key: String, value: String) -> HermesProviderCLIInvocation {
        let args = ["config", "set", key, value]
        return HermesProviderCLIInvocation(arguments: args, redactedArguments: args)
    }

    nonisolated private static func secretConfigSet(key: String, value: String) -> HermesProviderCLIInvocation {
        let args = ["config", "set", key, value]
        let redacted = ["config", "set", key, "<redacted>"]
        return HermesProviderCLIInvocation(arguments: args, redactedArguments: redacted)
    }

    nonisolated private static func providerConfigValue(
        for provider: ProviderKind,
        compatibility: ProviderCustomCompatibility
    ) -> String {
        switch provider {
        case .openAI:
            return "openai"
        case .anthropic:
            return "anthropic"
        case .openRouter:
            return "openrouter"
        case .ollama:
            return "ollama"
        case .custom:
            return compatibility.rawValue
        case .openAICodex:
            return "openai-codex"
        case .liteLLM:
            return "litellm"
        }
    }

    nonisolated private static func customConfigPrefix(for compatibility: ProviderCustomCompatibility) -> String {
        switch compatibility {
        case .openAI:
            return "OPENAI"
        case .anthropic:
            return "ANTHROPIC"
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
