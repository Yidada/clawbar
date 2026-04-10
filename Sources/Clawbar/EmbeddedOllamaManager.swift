import Foundation

enum EmbeddedOllamaRuntimeState: String, Equatable, Sendable {
    case missing
    case starting
    case ready
    case failed

    var title: String {
        switch self {
        case .missing:
            "未检测到 Ollama CLI"
        case .starting:
            "Ollama CLI 启动中"
        case .ready:
            "Ollama CLI 已就绪"
        case .failed:
            "Ollama CLI 启动失败"
        }
    }

    var statusLabel: String {
        switch self {
        case .missing:
            "缺失"
        case .starting:
            "启动中"
        case .ready:
            "已就绪"
        case .failed:
            "失败"
        }
    }
}

enum EmbeddedOllamaModelState: String, Equatable, Sendable {
    case unknown
    case missing
    case pulling
    case ready
    case failed

    var title: String {
        switch self {
        case .unknown:
            "Gemma 4 状态未知"
        case .missing:
            "Gemma 4 尚未下载"
        case .pulling:
            "Gemma 4 下载中"
        case .ready:
            "Gemma 4 已就绪"
        case .failed:
            "Gemma 4 下载失败"
        }
    }

    var statusLabel: String {
        switch self {
        case .unknown:
            "未知"
        case .missing:
            "未下载"
        case .pulling:
            "下载中"
        case .ready:
            "已就绪"
        case .failed:
            "失败"
        }
    }
}

struct EmbeddedOllamaCommandResult: Equatable, Sendable {
    let output: String
    let exitStatus: Int32
    let timedOut: Bool
}

@MainActor
final class EmbeddedOllamaManager: ObservableObject {
    static let shared = EmbeddedOllamaManager()

    typealias EnvironmentProvider = @Sendable () -> [String: String]
    typealias ResourceURLProvider = @Sendable () -> URL?
    typealias CommandRunner = @Sendable (
        _ executablePath: String,
        _ arguments: [String],
        _ environment: [String: String],
        _ timeout: TimeInterval
    ) -> EmbeddedOllamaCommandResult
    typealias ModelProbe = @Sendable (_ baseURL: URL, _ timeout: TimeInterval) async throws -> [String]
    typealias RuntimeInstaller = @Sendable (_ downloadURL: URL, _ installDirectoryPath: String) async throws -> String

    nonisolated static let bundledRuntimeDirectoryName = "OllamaRuntime"
    nonisolated static let supportedModelID = "gemma4"
    nonisolated static let defaultBaseURL = URL(string: "http://127.0.0.1:11434")!
    nonisolated static let defaultHostValue = "127.0.0.1:11434"
    nonisolated static let runtimeVersion = "v0.20.5"
    nonisolated static let runtimeAssetName = "ollama-darwin.tgz"
    nonisolated static let runtimeDownloadURL = URL(
        string: "https://github.com/ollama/ollama/releases/download/\(runtimeVersion)/\(runtimeAssetName)"
    )!
    nonisolated static let bundledCLIPathEnvironmentKey = "CLAWBAR_OLLAMA_CLI_PATH"
    nonisolated static let testCLIPathEnvironmentKey = "CLAWBAR_TEST_OLLAMA_CLI_PATH"
    nonisolated static let testManagedRuntimeDirectoryEnvironmentKey = "CLAWBAR_TEST_OLLAMA_RUNTIME_DIR"
    nonisolated static let testModelsDirectoryEnvironmentKey = "CLAWBAR_TEST_OLLAMA_MODELS_DIR"
    private nonisolated static let readinessPollAttempts = 15
    private nonisolated static let readinessPollIntervalNanoseconds: UInt64 = 1_000_000_000

    @Published private(set) var runtimeState: EmbeddedOllamaRuntimeState = .missing
    @Published private(set) var modelState: EmbeddedOllamaModelState = .unknown
    @Published private(set) var isRefreshing = false
    @Published private(set) var isPreparing = false
    @Published private(set) var cliPath: String?
    @Published private(set) var managedRuntimePath: String
    @Published private(set) var managedModelsPath: String
    @Published private(set) var detectedModels: [String] = []
    @Published private(set) var lastActionSummary = "等待准备"
    @Published private(set) var lastActionDetail = "Clawbar 会准备 Ollama CLI/runtime 和 gemma4。"
    @Published private(set) var lastCommandOutput = ""
    @Published private(set) var lastRefreshDate: Date?

    private let environmentProvider: EnvironmentProvider
    private let resourceURLProvider: ResourceURLProvider
    private let runCommand: CommandRunner
    private let probeModels: ModelProbe
    private let installRuntime: RuntimeInstaller
    private var serveProcess: Process?
    private var preparationTask: Task<Bool, Never>?
    private var refreshTask: Task<Void, Never>?

    init(
        environmentProvider: @escaping EnvironmentProvider = { ProcessInfo.processInfo.environment },
        resourceURLProvider: @escaping ResourceURLProvider = { Bundle.main.resourceURL },
        runCommand: @escaping CommandRunner = EmbeddedOllamaManager.runCommand,
        probeModels: @escaping ModelProbe = EmbeddedOllamaManager.probeModels,
        installRuntime: @escaping RuntimeInstaller = EmbeddedOllamaManager.installRuntime
    ) {
        self.environmentProvider = environmentProvider
        self.resourceURLProvider = resourceURLProvider
        self.runCommand = runCommand
        self.probeModels = probeModels
        self.installRuntime = installRuntime
        self.managedRuntimePath = Self.resolveManagedRuntimeDirectoryPath(environment: environmentProvider())
        self.managedModelsPath = Self.resolveManagedModelsPath(environment: environmentProvider())
    }

    deinit {
        serveProcess?.terminate()
    }

    var runtimeSummary: String {
        switch runtimeState {
        case .missing:
            "尚未检测到 Ollama CLI。可以在这里下载安装到 Clawbar 托管目录。"
        case .starting:
            "正在安装或启动本地 Ollama 服务。"
        case .ready:
            "服务地址固定为 \(Self.defaultBaseURL.absoluteString)。"
        case .failed:
            "请查看最近命令输出并重试安装或准备。"
        }
    }

    var modelSummary: String {
        switch modelState {
        case .unknown:
            "等待下一次探测。"
        case .missing:
            "Clawbar 还没有检测到 gemma4。"
        case .pulling:
            "Clawbar 正在下载 gemma4。"
        case .ready:
            "默认固定模型是 gemma4。"
        case .failed:
            "Clawbar 未能完成 gemma4 下载。"
        }
    }

    var isGemmaReady: Bool {
        runtimeState == .ready && detectedModels.contains(where: Self.matchesSupportedModel)
    }

    var needsRuntimeInstall: Bool {
        cliPath == nil
    }

    func refreshStatus() {
        guard refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshStatusCore()
            await MainActor.run {
                self.refreshTask = nil
            }
        }
    }

    func prepareRuntimeAndModel() {
        Task {
            _ = await ensureRuntimeAndModelReady(forceRefresh: true, allowInstall: true)
        }
    }

    func installRuntimeIfNeeded() {
        Task {
            _ = await ensureRuntimeAndModelReady(forceRefresh: true, allowInstall: true)
        }
    }

    func ensureRuntimeAndModelReady(
        forceRefresh: Bool = false,
        allowInstall: Bool = false
    ) async -> Bool {
        if let preparationTask {
            return await preparationTask.value
        }

        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.prepareRuntimeAndModelCore(
                forceRefresh: forceRefresh,
                allowInstall: allowInstall
            )
        }
        preparationTask = task
        let ready = await task.value
        preparationTask = nil
        return ready
    }

    private func refreshStatusCore() async {
        let environment = environmentProvider()
        let resolvedCLIPath = Self.resolveAvailableCLIPath(
            environment: environment,
            resourceURL: resourceURLProvider()
        )
        let runtimePath = Self.resolveManagedRuntimeDirectoryPath(environment: environment)
        let modelsPath = Self.resolveManagedModelsPath(environment: environment)

        await MainActor.run {
            self.isRefreshing = true
            self.cliPath = resolvedCLIPath
            self.managedRuntimePath = runtimePath
            self.managedModelsPath = modelsPath
        }

        guard let resolvedCLIPath else {
            await MainActor.run {
                self.runtimeState = .missing
                self.modelState = .unknown
                self.detectedModels = []
                self.lastActionSummary = "未检测到 Ollama CLI"
                self.lastActionDetail = "可以在当前页面下载安装官方 Ollama CLI/runtime。"
                self.lastRefreshDate = Date()
                self.isRefreshing = false
            }
            return
        }

        do {
            let models = try await probeModels(Self.defaultBaseURL, 2)
            await MainActor.run {
                self.runtimeState = .ready
                self.modelState = models.contains(where: Self.matchesSupportedModel) ? .ready : .missing
                self.detectedModels = models
                self.lastActionSummary = self.modelState == .ready ? "Ollama CLI 已就绪" : "Gemma 4 尚未下载"
                self.lastActionDetail = self.modelState == .ready
                    ? "已检测到 Ollama 服务和 gemma4。"
                    : "Ollama 服务可达，但当前还没有检测到 gemma4。"
                self.lastRefreshDate = Date()
                self.isRefreshing = false
                if self.lastCommandOutput.isEmpty {
                    self.lastCommandOutput = "$ \(resolvedCLIPath) serve\n# host: \(Self.defaultHostValue)\n# models: \(modelsPath)"
                }
            }
        } catch {
            await MainActor.run {
                self.runtimeState = .failed
                self.modelState = .unknown
                self.detectedModels = []
                self.lastActionSummary = "Ollama CLI 未就绪"
                self.lastActionDetail = error.localizedDescription
                self.lastRefreshDate = Date()
                self.isRefreshing = false
            }
        }
    }

    private func prepareRuntimeAndModelCore(
        forceRefresh: Bool,
        allowInstall: Bool
    ) async -> Bool {
        let environment = environmentProvider()
        var resolvedCLIPath = Self.resolveAvailableCLIPath(
            environment: environment,
            resourceURL: resourceURLProvider()
        )
        let runtimePath = Self.resolveManagedRuntimeDirectoryPath(environment: environment)
        let modelsPath = Self.resolveManagedModelsPath(environment: environment)

        await MainActor.run {
            self.isPreparing = true
            self.cliPath = resolvedCLIPath
            self.managedRuntimePath = runtimePath
            self.managedModelsPath = modelsPath
            self.lastRefreshDate = Date()
        }

        if resolvedCLIPath == nil {
            guard allowInstall else {
                await MainActor.run {
                    self.runtimeState = .missing
                    self.modelState = .unknown
                    self.detectedModels = []
                    self.isPreparing = false
                    self.lastActionSummary = "未检测到 Ollama CLI"
                    self.lastActionDetail = "可以在当前页面下载安装官方 Ollama CLI/runtime。"
                    self.lastCommandOutput = ""
                }
                return false
            }

            await MainActor.run {
                self.runtimeState = .starting
                self.modelState = .unknown
                self.lastActionSummary = "正在安装 Ollama CLI..."
                self.lastActionDetail = "Clawbar 正在下载安装官方 Ollama CLI/runtime。"
                self.lastCommandOutput = """
                $ curl -fsSL \(Self.runtimeDownloadURL.absoluteString)
                $ tar -xzf \(Self.runtimeAssetName) -C \(runtimePath)
                """
            }

            do {
                resolvedCLIPath = try await installRuntime(Self.runtimeDownloadURL, runtimePath)
                await MainActor.run {
                    self.cliPath = resolvedCLIPath
                }
            } catch {
                await MainActor.run {
                    self.runtimeState = .failed
                    self.modelState = .unknown
                    self.detectedModels = []
                    self.isPreparing = false
                    self.lastActionSummary = "Ollama CLI 安装失败"
                    self.lastActionDetail = error.localizedDescription
                }
                return false
            }
        }

        guard let resolvedCLIPath else {
            await MainActor.run {
                self.runtimeState = .missing
                self.modelState = .unknown
                self.detectedModels = []
                self.isPreparing = false
            }
            return false
        }

        let commandEnvironment = Self.makeCommandEnvironment(base: environment, modelsPath: modelsPath)

        if forceRefresh == false, let models = try? await probeModels(Self.defaultBaseURL, 2) {
            await MainActor.run {
                self.runtimeState = .ready
                self.detectedModels = models
                self.modelState = models.contains(where: Self.matchesSupportedModel) ? .ready : .missing
            }
        }

        if runtimeState != .ready {
            await MainActor.run {
                self.runtimeState = .starting
                self.lastActionSummary = "正在启动 Ollama CLI..."
                self.lastActionDetail = "Clawbar 正在拉起本地 ollama serve。"
                self.lastCommandOutput = "$ \(resolvedCLIPath) serve"
            }

            do {
                try Self.startServeProcessIfNeeded(
                    cliPath: resolvedCLIPath,
                    environment: commandEnvironment,
                    currentProcess: &serveProcess
                ) { [weak self] output in
                    Task { @MainActor in
                        guard let self, !output.isEmpty else { return }
                        self.lastCommandOutput = self.lastCommandOutput.isEmpty
                            ? output
                            : "\(self.lastCommandOutput)\n\(output)"
                    }
                }
            } catch {
                await MainActor.run {
                    self.runtimeState = .failed
                    self.modelState = .unknown
                    self.detectedModels = []
                    self.isPreparing = false
                    self.lastActionSummary = "Ollama CLI 启动失败"
                    self.lastActionDetail = error.localizedDescription
                }
                return false
            }

            var latestModels: [String] = []
            var runtimeReady = false

            for _ in 0..<Self.readinessPollAttempts {
                if let models = try? await probeModels(Self.defaultBaseURL, 2) {
                    latestModels = models
                    runtimeReady = true
                    break
                }
                try? await Task.sleep(nanoseconds: Self.readinessPollIntervalNanoseconds)
            }

            guard runtimeReady else {
                await MainActor.run {
                    self.runtimeState = .failed
                    self.modelState = .unknown
                    self.detectedModels = []
                    self.isPreparing = false
                    self.lastActionSummary = "Ollama CLI 未就绪"
                    self.lastActionDetail = "Clawbar 在等待 \(Self.defaultHostValue) 就绪时超时。"
                }
                return false
            }

            await MainActor.run {
                self.runtimeState = .ready
                self.detectedModels = latestModels
                self.modelState = latestModels.contains(where: Self.matchesSupportedModel) ? .ready : .missing
            }
        }

        if modelState != .ready {
            await MainActor.run {
                self.modelState = .pulling
                self.lastActionSummary = "正在下载 Gemma 4..."
                self.lastActionDetail = "Clawbar 正在使用 Ollama CLI 拉取 gemma4。"
                self.lastCommandOutput = "$ \(resolvedCLIPath) pull \(Self.supportedModelID)"
            }

            let pullResult = runCommand(
                resolvedCLIPath,
                ["pull", Self.supportedModelID],
                commandEnvironment,
                3600
            )

            let renderedOutput = pullResult.output.nonEmptyOr("(no output)")
            await MainActor.run {
                self.lastCommandOutput = "$ \(resolvedCLIPath) pull \(Self.supportedModelID)\n\(renderedOutput)"
            }

            guard !pullResult.timedOut, pullResult.exitStatus == 0 else {
                await MainActor.run {
                    self.modelState = .failed
                    self.isPreparing = false
                    self.lastActionSummary = "Gemma 4 下载失败"
                    self.lastActionDetail = pullResult.timedOut
                        ? "下载命令超时。"
                        : pullResult.output.nonEmptyOr("命令返回了非零退出码 \(pullResult.exitStatus)。")
                }
                return false
            }

            guard let models = try? await probeModels(Self.defaultBaseURL, 2),
                  models.contains(where: Self.matchesSupportedModel) else {
                await MainActor.run {
                    self.modelState = .failed
                    self.isPreparing = false
                    self.lastActionSummary = "Gemma 4 下载失败"
                    self.lastActionDetail = "pull 命令已完成，但当前还没有检测到 gemma4。"
                }
                return false
            }

            await MainActor.run {
                self.detectedModels = models
            }
        }

        let finalModels = (try? await probeModels(Self.defaultBaseURL, 2)) ?? detectedModels
        await MainActor.run {
            self.runtimeState = .ready
            self.modelState = finalModels.contains(where: Self.matchesSupportedModel) ? .ready : .missing
            self.detectedModels = finalModels
            self.isPreparing = false
            self.lastActionSummary = self.modelState == .ready ? "Ollama CLI 已就绪" : "Gemma 4 尚未下载"
            self.lastActionDetail = self.modelState == .ready
                ? "Clawbar 已准备好 Ollama runtime 和 gemma4。"
                : "Ollama runtime 已启动，但还没有检测到 gemma4。"
            self.lastRefreshDate = Date()
        }
        return finalModels.contains(where: Self.matchesSupportedModel)
    }

    nonisolated static func resolveAvailableCLIPath(
        environment: [String: String],
        resourceURL: URL?
    ) -> String? {
        if let override = trimmedNonEmpty(environment[testCLIPathEnvironmentKey]) {
            return override
        }

        if let override = trimmedNonEmpty(environment[bundledCLIPathEnvironmentKey]) {
            return override
        }

        if let bundledPath = resolveBundledCLIPath(resourceURL: resourceURL) {
            return bundledPath
        }

        return resolveManagedCLIPath(environment: environment)
    }

    nonisolated static func resolveManagedRuntimeDirectoryPath(
        environment: [String: String]
    ) -> String {
        if let override = trimmedNonEmpty(environment[testManagedRuntimeDirectoryEnvironmentKey]) {
            return override
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Clawbar", isDirectory: true)
            .appendingPathComponent("Ollama", isDirectory: true)
            .appendingPathComponent("runtime", isDirectory: true)
            .path
    }

    nonisolated static func resolveManagedModelsPath(
        environment: [String: String]
    ) -> String {
        if let override = trimmedNonEmpty(environment[testModelsDirectoryEnvironmentKey]) {
            return override
        }

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Clawbar", isDirectory: true)
            .appendingPathComponent("Ollama", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .path
    }

    private nonisolated static func resolveBundledCLIPath(resourceURL: URL?) -> String? {
        guard let resourceURL else { return nil }
        let candidate = resourceURL
            .appendingPathComponent(bundledRuntimeDirectoryName, isDirectory: true)
            .appendingPathComponent("ollama", isDirectory: false)
            .path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private nonisolated static func resolveManagedCLIPath(
        environment: [String: String]
    ) -> String? {
        let candidate = URL(fileURLWithPath: resolveManagedRuntimeDirectoryPath(environment: environment), isDirectory: true)
            .appendingPathComponent("ollama", isDirectory: false)
            .path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    private nonisolated static func makeCommandEnvironment(
        base: [String: String],
        modelsPath: String
    ) -> [String: String] {
        var environment = base
        environment["OLLAMA_MODELS"] = modelsPath
        environment["OLLAMA_HOST"] = defaultHostValue
        return environment
    }

    private nonisolated static func startServeProcessIfNeeded(
        cliPath: String,
        environment: [String: String],
        currentProcess: inout Process?,
        outputHandler: @escaping @Sendable (String) -> Void
    ) throws {
        if let currentProcess, currentProcess.isRunning {
            return
        }

        let modelsPath = environment["OLLAMA_MODELS"] ?? ""
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: modelsPath, isDirectory: true),
            withIntermediateDirectories: true
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["serve"]
        process.environment = environment

        let outputPipe = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputHandler(ChannelCommandSupport.sanitizeOutput(data))
        }

        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            outputHandler("[embedded-ollama] ollama serve exited with status \(process.terminationStatus)")
        }

        try process.run()
        currentProcess = process
    }

    nonisolated static func matchesSupportedModel(_ candidate: String) -> Bool {
        let trimmed = trimmedNonEmpty(candidate)?.lowercased() ?? ""
        return trimmed == supportedModelID || trimmed.hasPrefix("\(supportedModelID):")
    }

    nonisolated static func parseModelNames(from data: Data) -> [String] {
        guard
            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = payload["models"] as? [[String: Any]]
        else {
            return []
        }

        return models.compactMap { model in
            trimmedNonEmpty(model["name"] as? String)
        }
    }

    private nonisolated static func probeModels(
        baseURL: URL,
        timeout: TimeInterval
    ) async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw NSError(
                domain: "EmbeddedOllamaManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Ollama 服务返回了非成功状态。"]
            )
        }

        return parseModelNames(from: data)
    }

    private nonisolated static func installRuntime(
        downloadURL: URL,
        installDirectoryPath: String
    ) async throws -> String {
        let fileManager = FileManager.default
        let installDirectoryURL = URL(fileURLWithPath: installDirectoryPath, isDirectory: true)
        let parentDirectoryURL = installDirectoryURL.deletingLastPathComponent()
        let temporaryDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent(
            "clawbar-ollama-\(UUID().uuidString)",
            isDirectory: true
        )
        let archiveURL = temporaryDirectoryURL.appendingPathComponent(runtimeAssetName, isDirectory: false)

        try fileManager.createDirectory(at: parentDirectoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        defer {
            try? fileManager.removeItem(at: temporaryDirectoryURL)
        }

        let (downloadedURL, response) = try await URLSession.shared.download(from: downloadURL)
        if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
            throw NSError(
                domain: "EmbeddedOllamaManager",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "下载 Ollama CLI 失败，HTTP \(httpResponse.statusCode)。"]
            )
        }

        try? fileManager.removeItem(at: archiveURL)
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)
        try? fileManager.removeItem(at: installDirectoryURL)
        try fileManager.createDirectory(at: installDirectoryURL, withIntermediateDirectories: true)

        let extractResult = runCommand(
            executablePath: "/usr/bin/tar",
            arguments: ["-xzf", archiveURL.path, "-C", installDirectoryPath],
            environment: [:],
            timeout: 600
        )

        guard !extractResult.timedOut, extractResult.exitStatus == 0 else {
            throw NSError(
                domain: "EmbeddedOllamaManager",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: extractResult.timedOut
                        ? "解压 Ollama CLI 超时。"
                        : extractResult.output.nonEmptyOr("解压 Ollama CLI 失败。")
                ]
            )
        }

        let cliPath = installDirectoryURL.appendingPathComponent("ollama", isDirectory: false).path
        guard fileManager.fileExists(atPath: cliPath) else {
            throw NSError(
                domain: "EmbeddedOllamaManager",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "安装包已解压，但没有找到 ollama 可执行文件。"]
            )
        }

        let chmodResult = runCommand(
            executablePath: "/bin/chmod",
            arguments: ["+x", cliPath],
            environment: [:],
            timeout: 30
        )

        guard !chmodResult.timedOut, chmodResult.exitStatus == 0, fileManager.isExecutableFile(atPath: cliPath) else {
            throw NSError(
                domain: "EmbeddedOllamaManager",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Ollama CLI 安装完成，但无法设置可执行权限。"]
            )
        }

        return cliPath
    }

    private nonisolated static func runCommand(
        executablePath: String,
        arguments: [String],
        environment: [String: String],
        timeout: TimeInterval
    ) -> EmbeddedOllamaCommandResult {
        let result = ChannelCommandSupport.runCommand(
            executablePath,
            arguments,
            environment,
            timeout
        )
        return EmbeddedOllamaCommandResult(
            output: result.output,
            exitStatus: result.exitStatus,
            timedOut: result.timedOut
        )
    }
}

private extension String {
    func nonEmptyOr(_ fallback: String) -> String {
        trimmedNonEmpty(self) ?? fallback
    }
}
