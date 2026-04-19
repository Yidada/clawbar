import Foundation

struct HermesStatusSnapshot: Equatable, Sendable {
    let isInstalled: Bool
    let hermesBinaryPath: String?
    let uvBinaryPath: String?
    let runtimeVersion: String?
    let defaultModel: String?
}

enum HermesInstallerError: LocalizedError {
    case missingUV
    case commandFailed(operationName: String, exitStatus: Int32, logURL: URL)
    case launchFailed(operationName: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .missingUV:
            "未找到 uv，需要先通过官方脚本安装 uv 才能继续。"
        case let .commandFailed(operationName, exitStatus, logURL):
            "Hermes \(operationName) 失败（退出码 \(exitStatus)）。日志：\(logURL.path)"
        case let .launchFailed(operationName, error):
            "无法启动 Hermes \(operationName)：\(error.localizedDescription)"
        }
    }
}

private enum HermesOperation {
    case installUV
    case install
    case upgrade
    case uninstall

    var displayName: String {
        switch self {
        case .installUV:
            "安装 uv"
        case .install:
            "安装"
        case .upgrade:
            "升级"
        case .uninstall:
            "卸载"
        }
    }

    var logFilename: String {
        switch self {
        case .installUV:
            "hermes-uv-install.log"
        case .install:
            "hermes-install.log"
        case .upgrade:
            "hermes-upgrade.log"
        case .uninstall:
            "hermes-uninstall.log"
        }
    }
}

@MainActor
final class HermesInstaller: ObservableObject {
    typealias CommandRunner = ChannelCommandSupport.CommandRunner
    typealias ConfigReader = @Sendable (URL) -> String?
    typealias ProcessFactory = @Sendable (
        _ command: String,
        _ logURL: URL,
        _ environment: [String: String],
        _ outputHandler: @escaping @Sendable (String) -> Void,
        _ completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws -> Process

    static let shared = HermesInstaller()
    nonisolated static let defaultRefreshInterval: TimeInterval = 300
    nonisolated static let uvInstallCommand = "curl -LsSf https://astral.sh/uv/install.sh | sh"
    nonisolated static let hermesInstallCommand = "uv tool install --force hermes-agent"
    nonisolated static let hermesUpgradeCommand = "uv tool upgrade hermes-agent"
    nonisolated static let hermesUninstallCommand = "uv tool uninstall hermes-agent"
    nonisolated static let detectUVCommand = "uv"
    nonisolated static let detectHermesCommand = "hermes"
    nonisolated static let versionTimeout: TimeInterval = 5

    @Published private(set) var isInstalled = false
    @Published private(set) var isInstalling = false
    @Published private(set) var isUninstalling = false
    @Published private(set) var isUpdating = false
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var hermesVersion: String?
    @Published private(set) var defaultModel: String?
    @Published private(set) var hermesBinaryPath: String?
    @Published private(set) var uvBinaryPath: String?
    @Published private(set) var healthSnapshot: AgentHealthSnapshot?
    @Published private(set) var lastRefreshDate: Date?
    @Published private(set) var statusText = "准备安装 Hermes Agent。"
    @Published private(set) var detailText = "Clawbar 会通过 uv 安装并管理 hermes-agent；首次安装会自动检查 uv 是否就绪。"
    @Published private(set) var logText = ""
    @Published private(set) var lastLogURL: URL = HermesInstaller.defaultLogURL(filename: "hermes-install.log")
    @Published private(set) var lastError: String?

    private let runCommand: CommandRunner
    private let processFactory: ProcessFactory
    private let configReader: ConfigReader
    private let homeOverride: URL?
    private let nowProvider: @Sendable () -> Date
    private let refreshInterval: TimeInterval
    private var activeProcess: Process?

    var isBusy: Bool {
        isInstalling || isUninstalling || isUpdating
    }

    init(
        refreshInterval: TimeInterval = HermesInstaller.defaultRefreshInterval,
        homeOverride: URL? = nil,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        runCommand: @escaping CommandRunner = ChannelCommandSupport.runCommand,
        configReader: @escaping ConfigReader = HermesInstaller.defaultConfigReader,
        processFactory: @escaping ProcessFactory = HermesInstaller.makeStreamingProcess
    ) {
        self.refreshInterval = refreshInterval
        self.homeOverride = homeOverride
        self.nowProvider = nowProvider
        self.runCommand = runCommand
        self.configReader = configReader
        self.processFactory = processFactory
    }

    func refreshStatus(force: Bool = false) async {
        if isRefreshingStatus { return }
        if !force, let last = lastRefreshDate, nowProvider().timeIntervalSince(last) < refreshInterval {
            return
        }

        isRefreshingStatus = true
        defer { isRefreshingStatus = false }

        let env = ChannelCommandSupport.commandEnvironment(base: ProcessInfo.processInfo.environment)
        let runner = runCommand
        let configReader = configReader
        let configURL = configFileURL()

        let snapshot = await Task.detached(priority: .utility) { @Sendable in
            return Self.collectStatusSnapshot(
                environment: env,
                runCommand: runner,
                configReader: configReader,
                configURL: configURL
            )
        }.value

        applyStatusSnapshot(snapshot)
        lastRefreshDate = nowProvider()
    }

    func startInstallIfNeeded() async {
        guard !isBusy else {
            statusText = "Hermes 正在处理中。"
            detailText = "请等待当前 Hermes 操作结束。"
            return
        }

        let env = ChannelCommandSupport.commandEnvironment(base: ProcessInfo.processInfo.environment)
        let uvDetected = ChannelCommandSupport.detectBinaryPath(
            named: Self.detectUVCommand,
            environment: env,
            runCommand: runCommand
        )

        isInstalling = true
        defer { isInstalling = false }
        lastError = nil
        logText = ""

        if uvDetected == nil {
            statusText = "正在安装 uv..."
            detailText = "首次安装 Hermes 需要 uv（Astral 提供的 Python 工具链管理器）。"
            do {
                try await runStreamingOperation(.installUV, command: Self.uvInstallCommand, environment: env)
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                statusText = "uv 安装失败。"
                detailText = lastError ?? "请检查网络连接或手动执行 \(Self.uvInstallCommand)。"
                return
            }
        }

        statusText = "正在安装 hermes-agent..."
        detailText = "uv tool install hermes-agent 会创建独立的 Python 环境，避免污染全局 site-packages。"

        do {
            try await runStreamingOperation(.install, command: Self.hermesInstallCommand, environment: env)
            statusText = "Hermes 安装完成。"
            detailText = "正在刷新 Hermes 状态..."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Hermes 安装失败。"
            detailText = lastError ?? "请检查日志以定位失败原因。"
        }

        await refreshStatus(force: true)
    }

    func startUpgradeIfNeeded() async {
        guard !isBusy else { return }
        let env = ChannelCommandSupport.commandEnvironment(base: ProcessInfo.processInfo.environment)
        isUpdating = true
        defer { isUpdating = false }
        lastError = nil
        logText = ""
        statusText = "正在升级 hermes-agent..."
        detailText = "uv tool upgrade hermes-agent 会拉取最新版本并替换隔离环境。"

        do {
            try await runStreamingOperation(.upgrade, command: Self.hermesUpgradeCommand, environment: env)
            statusText = "Hermes 升级完成。"
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Hermes 升级失败。"
            detailText = lastError ?? "请检查日志。"
        }

        await refreshStatus(force: true)
    }

    func startUninstallIfNeeded() async {
        guard !isBusy else { return }
        let env = ChannelCommandSupport.commandEnvironment(base: ProcessInfo.processInfo.environment)
        isUninstalling = true
        defer { isUninstalling = false }
        lastError = nil
        logText = ""
        statusText = "正在卸载 hermes-agent..."
        detailText = "卸载会移除 uv tool 环境，但 ~/.hermes/ 数据保留以便重新安装后继续使用。"

        do {
            try await runStreamingOperation(.uninstall, command: Self.hermesUninstallCommand, environment: env)
            statusText = "Hermes 已卸载。"
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusText = "Hermes 卸载失败。"
            detailText = lastError ?? "请检查日志。"
        }

        await refreshStatus(force: true)
    }

    func cancelActiveOperation() {
        guard let process = activeProcess, process.isRunning else { return }
        process.terminate()
    }

    func configFileURL() -> URL {
        hermesHomeURL().appendingPathComponent("config.yaml")
    }

    func envFileURL() -> URL {
        hermesHomeURL().appendingPathComponent(".env")
    }

    func hermesHomeURL() -> URL {
        if let homeOverride { return homeOverride }
        if let env = ProcessInfo.processInfo.environment["HERMES_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hermes", isDirectory: true)
    }

    private func applyStatusSnapshot(_ snapshot: HermesStatusSnapshot) {
        isInstalled = snapshot.isInstalled
        hermesBinaryPath = snapshot.hermesBinaryPath
        uvBinaryPath = snapshot.uvBinaryPath
        hermesVersion = snapshot.runtimeVersion
        defaultModel = snapshot.defaultModel
        healthSnapshot = Self.composeSnapshot(snapshot, configURL: configFileURL())

        if !isBusy {
            if snapshot.isInstalled {
                statusText = snapshot.runtimeVersion.map { "Hermes \($0) 已安装。" } ?? "Hermes 已安装。"
                detailText = snapshot.defaultModel.map { "默认模型：\($0)" } ?? "尚未设置默认模型，可在 Provider 面板里配置。"
            } else if snapshot.uvBinaryPath != nil {
                statusText = "已检测到 uv，但 Hermes 未安装。"
                detailText = "点击 Install 即可执行 uv tool install hermes-agent。"
            } else {
                statusText = "尚未安装 Hermes Agent。"
                detailText = "点击 Install 后会先安装 uv，再安装 hermes-agent。"
            }
        }
    }

    private func runStreamingOperation(
        _ operation: HermesOperation,
        command: String,
        environment: [String: String]
    ) async throws {
        let logURL = Self.defaultLogURL(filename: operation.logFilename)
        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        lastLogURL = logURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let process = try processFactory(
                    command,
                    logURL,
                    environment,
                    { [weak self] chunk in
                        Task { @MainActor in
                            self?.appendLog(chunk)
                        }
                    },
                    { result in
                        Task { @MainActor in
                            self.activeProcess = nil
                        }
                        continuation.resume(with: result)
                    }
                )
                activeProcess = process
                try process.run()
            } catch {
                continuation.resume(throwing: HermesInstallerError.launchFailed(
                    operationName: operation.displayName,
                    underlyingError: error
                ))
            }
        }
    }

    private func appendLog(_ chunk: String) {
        logText += chunk
        if let data = chunk.data(using: .utf8),
           let handle = try? FileHandle(forWritingTo: lastLogURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    nonisolated static func defaultLogURL(filename: String) -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return libraryURL
            .appending(path: "Logs")
            .appending(path: "Clawbar")
            .appending(path: filename)
    }

    nonisolated static func defaultConfigReader(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    nonisolated static func makeStreamingProcess(
        command: String,
        logURL: URL,
        environment: [String: String],
        outputHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws -> Process {
        return try ChannelCommandSupport.makeStreamingProcess(
            command: command,
            environment: environment,
            outputHandler: outputHandler,
            terminationHandler: { exitCode in
                if exitCode == 0 {
                    completion(.success(()))
                } else {
                    completion(.failure(HermesInstallerError.commandFailed(
                        operationName: "命令",
                        exitStatus: exitCode,
                        logURL: logURL
                    )))
                }
            }
        )
    }

    nonisolated static func collectStatusSnapshot(
        environment: [String: String],
        runCommand: CommandRunner,
        configReader: ConfigReader,
        configURL: URL
    ) -> HermesStatusSnapshot {
        let uvPath = ChannelCommandSupport.detectBinaryPath(
            named: detectUVCommand,
            environment: environment,
            runCommand: runCommand
        )
        let hermesPath = ChannelCommandSupport.detectBinaryPath(
            named: detectHermesCommand,
            environment: environment,
            runCommand: runCommand
        )

        var version: String?
        if let hermesPath {
            let result = runCommand(hermesPath, ["--version"], environment, versionTimeout)
            if !result.timedOut, result.exitStatus == 0 {
                version = parseVersion(result.output)
            }
        }

        let defaultModel = configReader(configURL).flatMap(parseDefaultModel)

        return HermesStatusSnapshot(
            isInstalled: hermesPath != nil,
            hermesBinaryPath: hermesPath,
            uvBinaryPath: uvPath,
            runtimeVersion: version,
            defaultModel: defaultModel
        )
    }

    nonisolated static func parseVersion(_ output: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"v([0-9]+(?:\.[0-9A-Za-z]+)+)"#) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[valueRange])
    }

    nonisolated static func parseDefaultModel(_ yaml: String) -> String? {
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        var inModelBlock = false
        for raw in lines {
            let line = String(raw)
            let stripped = stripComment(line)
            let trimmed = stripped.trimmingCharacters(in: .whitespaces)

            if let value = matchKey("model", in: stripped) {
                let trimmedValue = value.trimmingCharacters(in: .whitespaces)
                if !trimmedValue.isEmpty {
                    return unquote(trimmedValue)
                }
                inModelBlock = true
                continue
            }

            if inModelBlock {
                if stripped.hasPrefix(" ") || stripped.hasPrefix("\t") {
                    if let nested = matchKey("default", in: trimmed) {
                        return unquote(nested.trimmingCharacters(in: .whitespaces))
                    }
                } else if !trimmed.isEmpty {
                    inModelBlock = false
                }
            }
        }
        return nil
    }

    nonisolated static func composeSnapshot(_ snapshot: HermesStatusSnapshot, configURL: URL) -> AgentHealthSnapshot {
        let providerLevel: AgentHealthLevel
        let providerStatus: String
        let providerSummary: String
        let providerDetail: String

        if !snapshot.isInstalled {
            providerLevel = .unknown
            providerStatus = "等待安装"
            providerSummary = "尚未安装 hermes-agent"
            providerDetail = "请先安装 Hermes 后再配置 Provider。"
        } else if let model = snapshot.defaultModel {
            providerLevel = .healthy
            providerStatus = "已配置"
            providerSummary = model
            providerDetail = "默认模型来自 \(configURL.path)。"
        } else {
            providerLevel = .warning
            providerStatus = "未配置"
            providerSummary = "Hermes 默认模型未设置"
            providerDetail = "在 Provider 面板里选择模型，或运行 hermes config set model.default <id>。"
        }

        let gatewayLevel: AgentHealthLevel
        let gatewayStatus: String
        let gatewaySummary: String
        let gatewayDetail: String

        if snapshot.isInstalled {
            gatewayLevel = .unknown
            gatewayStatus = "等待刷新"
            gatewaySummary = "Hermes Gateway 状态待查询"
            gatewayDetail = "Hermes Gateway 服务状态会在 Gateway 面板里展示。"
        } else {
            gatewayLevel = .unknown
            gatewayStatus = "等待安装"
            gatewaySummary = "未安装 Hermes Agent"
            gatewayDetail = "请先安装 Hermes 后再配置 Messaging Gateway。"
        }

        return AgentHealthSnapshot(
            runtimeVersion: snapshot.runtimeVersion,
            dimensions: [
                AgentHealthDimensionSnapshot(
                    dimension: .provider,
                    level: providerLevel,
                    statusLabel: providerStatus,
                    summary: providerSummary,
                    detail: providerDetail
                ),
                AgentHealthDimensionSnapshot(
                    dimension: .gateway,
                    level: gatewayLevel,
                    statusLabel: gatewayStatus,
                    summary: gatewaySummary,
                    detail: gatewayDetail
                ),
            ]
        )
    }

    nonisolated private static func stripComment(_ line: String) -> String {
        guard let hashIndex = line.firstIndex(of: "#") else { return line }
        return String(line[..<hashIndex])
    }

    nonisolated private static func matchKey(_ key: String, in line: String) -> String? {
        let prefix = key + ":"
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard trimmedLine.hasPrefix(prefix) else { return nil }
        return String(trimmedLine.dropFirst(prefix.count))
    }

    nonisolated private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        let first = value.first!
        let last = value.last!
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
