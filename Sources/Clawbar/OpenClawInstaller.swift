import Foundation

private enum OpenClawOperation {
    case install
    case uninstall

    var command: String {
        switch self {
        case .install:
            OpenClawInstaller.installCommand
        case .uninstall:
            OpenClawInstaller.uninstallCommand
        }
    }

    var actionName: String {
        switch self {
        case .install:
            "安装"
        case .uninstall:
            "卸载"
        }
    }

    var logURL: URL {
        switch self {
        case .install:
            OpenClawInstaller.defaultLogURL(filename: "openclaw-install.log")
        case .uninstall:
            OpenClawInstaller.defaultLogURL(filename: "openclaw-uninstall.log")
        }
    }

    var logTitle: String {
        switch self {
        case .install:
            "安装日志"
        case .uninstall:
            "卸载日志"
        }
    }

    var placeholderLogText: String {
        switch self {
        case .install:
            "等待安装输出..."
        case .uninstall:
            "等待卸载输出..."
        }
    }

    var idleStatusText: String {
        switch self {
        case .install:
            "准备安装 OpenClaw。"
        case .uninstall:
            "准备卸载 OpenClaw。"
        }
    }

    var idleDetailText: String {
        switch self {
        case .install:
            "点击按钮后会执行官方安装脚本，但不会进入 onboarding。"
        case .uninstall:
            "点击按钮后会执行官方非交互卸载，并移除全局 openclaw CLI。"
        }
    }

    var startingStatusText: String {
        switch self {
        case .install:
            "正在启动 OpenClaw 安装..."
        case .uninstall:
            "正在启动 OpenClaw 卸载..."
        }
    }

    var startingDetailText: String {
        switch self {
        case .install:
            "这会执行官方安装脚本，并把输出实时写入日志窗口。"
        case .uninstall:
            "这会执行官方非交互卸载命令，并把输出实时写入日志窗口。"
        }
    }

    var runningStatusText: String {
        switch self {
        case .install:
            "正在安装 OpenClaw..."
        case .uninstall:
            "正在卸载 OpenClaw..."
        }
    }

    var runningDetailText: String {
        switch self {
        case .install:
            "官方脚本没有稳定的百分比接口，所以这里显示实时输出和当前状态。"
        case .uninstall:
            "卸载过程会清理本机 OpenClaw 数据，并移除全局 CLI。"
        }
    }
}

struct OpenClawStatusSnapshot: Equatable, Sendable {
    let title: String
    let detail: String
    let excerpt: String?
    let binaryPath: String
}

struct OpenClawInstallerOverride: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case missing
        case installed(OpenClawStatusSnapshot)
    }

    let state: State

    static func from(environment: [String: String]) -> Self? {
        guard let rawState = environment["CLAWBAR_TEST_OPENCLAW_STATE"]?.lowercased() else {
            return nil
        }

        switch rawState {
        case "missing":
            return Self(state: .missing)
        case "installed":
            let binaryPath = environment["CLAWBAR_TEST_OPENCLAW_BINARY_PATH"] ?? "/opt/homebrew/bin/openclaw"
            let snapshot = OpenClawStatusSnapshot(
                title: environment["CLAWBAR_TEST_OPENCLAW_TITLE"] ?? "OpenClaw 已安装",
                detail: environment["CLAWBAR_TEST_OPENCLAW_DETAIL"] ?? "status 已返回最近状态。",
                excerpt: environment["CLAWBAR_TEST_OPENCLAW_EXCERPT"],
                binaryPath: OpenClawInstaller.displayBinaryPath(binaryPath)
            )
            return Self(state: .installed(snapshot))
        default:
            return nil
        }
    }
}

enum OpenClawInstallerError: LocalizedError {
    case commandFailed(operationName: String, status: Int32, logURL: URL)
    case launchFailed(operationName: String, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(operationName, status, logURL):
            "OpenClaw \(operationName)失败，退出码 \(status)。日志位置：\(logURL.path)"
        case let .launchFailed(operationName, underlyingError):
            "无法启动 OpenClaw \(operationName)：\(underlyingError.localizedDescription)"
        }
    }
}

@MainActor
final class OpenClawInstaller: ObservableObject {
    static let shared: OpenClawInstaller = {
        let environment = ProcessInfo.processInfo.environment
        let overrideState = OpenClawInstallerOverride.from(environment: environment)
        return OpenClawInstaller(overrideState: overrideState, autoStartTimer: overrideState == nil)
    }()
    nonisolated static let defaultRefreshInterval: TimeInterval = 30
    nonisolated static let installScriptURL = URL(string: "https://openclaw.ai/install.sh")!
    nonisolated static let installCommand = "curl -fsSL \(installScriptURL.absoluteString) | bash -s -- --no-onboard"
    nonisolated static let uninstallCommand = "openclaw uninstall --all --yes --non-interactive && npm rm -g openclaw"
    nonisolated static let detectCommand = "command -v openclaw"
    nonisolated static let statusCommand = "openclaw status"

    @Published private(set) var isInstalling = false
    @Published private(set) var isUninstalling = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var statusText = OpenClawOperation.install.idleStatusText
    @Published private(set) var detailText = OpenClawOperation.install.idleDetailText
    @Published private(set) var installedBinaryPath: String?
    @Published private(set) var statusExcerpt: String?
    @Published private(set) var logText = ""
    @Published private(set) var lastLogURL = OpenClawOperation.install.logURL
    @Published private(set) var lastStatusRefreshDate: Date?

    private var activeProcess: Process?
    private var outputHandle: FileHandle?
    private let refreshInterval: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private let overrideState: OpenClawInstallerOverride?
    private var refreshTimer: Timer?
    private var lastOperation: OpenClawOperation = .install

    init(
        refreshInterval: TimeInterval = OpenClawInstaller.defaultRefreshInterval,
        nowProvider: @escaping @Sendable () -> Date = Date.init,
        overrideState: OpenClawInstallerOverride? = nil,
        autoStartTimer: Bool = true
    ) {
        self.refreshInterval = refreshInterval
        self.nowProvider = nowProvider
        self.overrideState = overrideState

        if autoStartTimer, overrideState == nil {
            startPeriodicRefresh()
        }
    }

    var isBusy: Bool {
        isInstalling || isUninstalling
    }

    var operationLogTitle: String {
        activeOperation.logTitle
    }

    var operationHintText: String {
        switch activeOperation {
        case .install:
            "说明：官方安装脚本没有提供稳定的百分比进度，所以这里展示实时输出和当前状态。"
        case .uninstall:
            "说明：卸载会先执行 OpenClaw 官方非交互卸载，再移除通过安装脚本落下的全局 CLI。"
        }
    }

    var emptyLogPlaceholder: String {
        activeOperation.placeholderLogText
    }

    func refreshInstallationStatus(force: Bool = false) {
        if let overrideState {
            applyOverrideState(overrideState)
            return
        }

        let now = nowProvider()
        guard Self.shouldRefreshStatus(
            force: force,
            isRefreshing: isRefreshingStatus,
            lastRefreshDate: lastStatusRefreshDate,
            now: now,
            refreshInterval: refreshInterval
        ) else {
            return
        }

        let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
        isRefreshingStatus = true

        Task.detached(priority: .utility) {
            let path = Self.detectInstalledBinaryPath(environment: environment)
            let snapshot = path.map { binaryPath in
                Self.fetchStatusSnapshot(binaryPath: binaryPath, environment: environment)
            }

            await MainActor.run {
                self.isRefreshingStatus = false
                self.lastStatusRefreshDate = self.nowProvider()
                self.isInstalled = path != nil
                self.installedBinaryPath = path
                self.statusExcerpt = snapshot?.excerpt

                guard !self.isBusy else { return }

                if let snapshot {
                    self.statusText = snapshot.title
                    self.detailText = snapshot.detail
                } else {
                    self.statusText = OpenClawOperation.install.idleStatusText
                    self.detailText = OpenClawOperation.install.idleDetailText
                }
            }
        }
    }

    private func applyOverrideState(_ overrideState: OpenClawInstallerOverride) {
        isRefreshingStatus = false
        lastStatusRefreshDate = nowProvider()

        switch overrideState.state {
        case .missing:
            isInstalled = false
            installedBinaryPath = nil
            statusExcerpt = nil
            if !isBusy {
                statusText = OpenClawOperation.install.idleStatusText
                detailText = OpenClawOperation.install.idleDetailText
            }
        case let .installed(snapshot):
            isInstalled = true
            installedBinaryPath = snapshot.binaryPath
            statusExcerpt = snapshot.excerpt
            if !isBusy {
                statusText = snapshot.title
                detailText = snapshot.detail
            }
        }
    }

    func startInstallIfNeeded() {
        if isBusy {
            statusText = "OpenClaw 正在处理中。"
            detailText = "请等待当前安装或卸载流程结束。"
            return
        }

        startOperation(.install)
    }

    func startUninstallIfNeeded() {
        if isBusy {
            statusText = "OpenClaw 正在处理中。"
            detailText = "请等待当前安装或卸载流程结束。"
            return
        }

        startOperation(.uninstall)
    }

    nonisolated static func defaultLogURL(filename: String) -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return libraryURL
            .appending(path: "Logs")
            .appending(path: "Clawbar")
            .appending(path: filename)
    }

    nonisolated static func installationEnvironment(base: [String: String]) -> [String: String] {
        var environment = base
        let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

        if let currentPath = environment["PATH"], !currentPath.isEmpty {
            if !currentPath.contains("/opt/homebrew/bin") {
                environment["PATH"] = "\(defaultPath):\(currentPath)"
            }
        } else {
            environment["PATH"] = defaultPath
        }

        return environment
    }

    nonisolated static func parseDetectedBinaryPath(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    nonisolated static func displayBinaryPath(_ path: String) -> String {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(homePath + "/") {
            return "~" + path.dropFirst(homePath.count)
        }
        return path
    }

    nonisolated static func summarizeStatusLine(_ line: String, maxLength: Int = 88) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let normalized = trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if normalized.hasPrefix("[plugins] plugins.allow is empty") {
            return "plugins.allow is empty; discovered non-bundled plugins."
        }

        if normalized.count <= maxLength {
            return normalized
        }

        let index = normalized.index(normalized.startIndex, offsetBy: maxLength - 1)
        return String(normalized[..<index]) + "…"
    }

    nonisolated static func shouldRefreshStatus(
        force: Bool,
        isRefreshing: Bool,
        lastRefreshDate: Date?,
        now: Date,
        refreshInterval: TimeInterval
    ) -> Bool {
        if isRefreshing {
            return false
        }

        if force || lastRefreshDate == nil {
            return true
        }

        guard let lastRefreshDate else {
            return true
        }

        return now.timeIntervalSince(lastRefreshDate) >= refreshInterval
    }

    nonisolated static func makeStatusSnapshot(binaryPath: String, commandOutput: String, timedOut: Bool) -> OpenClawStatusSnapshot {
        let normalizedOutput = commandOutput
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let displayPath = displayBinaryPath(binaryPath)

        if timedOut {
            return OpenClawStatusSnapshot(
                title: "OpenClaw 已安装",
                detail: "status 命令未在 3 秒内完成。",
                excerpt: normalizedOutput.first.map { summarizeStatusLine($0) },
                binaryPath: displayPath
            )
        }

        if let firstLine = normalizedOutput.first {
            return OpenClawStatusSnapshot(
                title: "OpenClaw 已安装",
                detail: "status 已返回最近状态。",
                excerpt: summarizeStatusLine(firstLine),
                binaryPath: displayPath
            )
        }

        return OpenClawStatusSnapshot(
            title: "OpenClaw 已安装",
            detail: "已检测到全局命令，但 status 暂无可显示输出。",
            excerpt: nil,
            binaryPath: displayPath
        )
    }

    private nonisolated static func makeProcess(
        command: String,
        logURL: URL,
        environment: [String: String],
        outputHandler: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void
    ) throws -> Process {
        try prepareLogFile(at: logURL)

        let outputPipe = Pipe()
        let outputHandle = try FileHandle(forWritingTo: logURL)
        let process = Process()

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            try? outputHandle.write(contentsOf: data)
            outputHandler(sanitizeOutput(data))
        }

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputHandle.close()

            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                completion(.failure(OpenClawInstallerError.commandFailed(operationName: operationName(for: command), status: process.terminationStatus, logURL: logURL)))
            }
        }

        return process
    }

    private nonisolated static func prepareLogFile(at logURL: URL) throws {
        let directoryURL = logURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: logURL.path) {
            try FileManager.default.removeItem(at: logURL)
        }

        FileManager.default.createFile(atPath: logURL.path, contents: Data())
    }

    private nonisolated static func detectInstalledBinaryPath(environment: [String: String]) -> String? {
        detectCommandPath(detectCommand, environment: environment)
    }

    private nonisolated static func detectCommandPath(_ command: String, environment: [String: String]) -> String? {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                return nil
            }

            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            return parseDetectedBinaryPath(String(decoding: data, as: UTF8.self))
        } catch {
            return nil
        }
    }

    private nonisolated static func fetchStatusSnapshot(binaryPath: String, environment: [String: String]) -> OpenClawStatusSnapshot {
        let result = runCommand(statusCommand, environment: environment, timeout: 3)
        return makeStatusSnapshot(
            binaryPath: binaryPath,
            commandOutput: result.output,
            timedOut: result.timedOut
        )
    }

    private nonisolated static func runCommand(
        _ command: String,
        environment: [String: String],
        timeout: TimeInterval
    ) -> (output: String, exitStatus: Int32, timedOut: Bool) {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", command]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return ("", 1, false)
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
        return (sanitizeOutput(data), process.terminationStatus, timedOut)
    }

    private func appendLog(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        logText += chunk
    }

    private var activeOperation: OpenClawOperation {
        lastOperation
    }

    private func startOperation(_ operation: OpenClawOperation) {
        let logURL = operation.logURL
        let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
        lastOperation = operation
        lastLogURL = logURL
        logText = "$ \(operation.command)\n\n"
        statusText = operation.startingStatusText
        detailText = operation.startingDetailText

        do {
            let process = try Self.makeProcess(
                command: operation.command,
                logURL: logURL,
                environment: environment,
                outputHandler: { [weak self] chunk in
                    Task { @MainActor in
                        guard let self else { return }
                        self.appendLog(chunk)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.finishOperation(operation, with: result, logURL: logURL)
                    }
                }
            )

            try process.run()
            activeProcess = process
            isInstalling = operation == .install
            isUninstalling = operation == .uninstall
            statusText = operation.runningStatusText
            detailText = operation.runningDetailText
        } catch {
            finishOperation(operation, with: .failure(OpenClawInstallerError.launchFailed(operationName: operation.actionName, underlyingError: error)), logURL: logURL)
        }
    }

    private func finishInstall(with result: Result<Void, Error>, logURL: URL) {
        activeProcess = nil
        outputHandle = nil
        lastLogURL = logURL

        switch result {
        case .success:
            let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
            let openClawPath = Self.detectInstalledBinaryPath(environment: environment)

            guard openClawPath != nil else {
                isInstalling = false
                statusText = "OpenClaw 安装完成。"
                detailText = "安装脚本执行结束，但尚未检测到全局 openclaw 命令。"
                logText += "\n[Clawbar] OpenClaw 安装完成，但未检测到全局 openclaw 命令。\n"
                refreshInstallationStatus(force: true)
                return
            }

            do {
                let token = try OpenClawGatewayCredentialStore.shared.ensureGatewayTokenConfigured()
                logText += "\n[Clawbar] 已为 Gateway 准备本地 token：\(token.prefix(12))...\n"
            } catch {
                logText += "\n[Clawbar] Gateway token 初始化失败：\(error.localizedDescription)\n"
            }

            let snapshot = openClawPath.map {
                Self.fetchStatusSnapshot(binaryPath: $0, environment: environment)
            }
            isInstalling = false
            isInstalled = true
            installedBinaryPath = openClawPath
            statusExcerpt = snapshot?.excerpt
            lastStatusRefreshDate = nowProvider()
            statusText = "OpenClaw 安装完成。"
            detailText = "下一步可前往 Channels 页，按需安装和绑定微信能力。"
            logText += "\n[Clawbar] OpenClaw 安装完成；微信能力已改为在 Channels 页独立安装。\n"
        case let .failure(error):
            isInstalling = false
            statusText = "OpenClaw 安装失败。"
            detailText = error.localizedDescription
            logText += "\n[Clawbar] \(error.localizedDescription)\n"
        }
    }

    private func startPeriodicRefresh() {
        guard refreshTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshInstallationStatus(force: true)
            }
        }
        timer.tolerance = min(5, refreshInterval * 0.2)
        refreshTimer = timer
    }

    private func finishOperation(_ operation: OpenClawOperation, with result: Result<Void, Error>, logURL: URL) {
        switch operation {
        case .install:
            finishInstall(with: result, logURL: logURL)
        case .uninstall:
            finishUninstall(with: result, logURL: logURL)
        }
    }

    private func finishUninstall(with result: Result<Void, Error>, logURL: URL) {
        activeProcess = nil
        outputHandle = nil
        lastLogURL = logURL
        isInstalling = false
        isUninstalling = false

        switch result {
        case .success:
            isInstalled = false
            installedBinaryPath = nil
            statusExcerpt = nil
            lastStatusRefreshDate = nowProvider()
            statusText = "OpenClaw 已卸载。"
            detailText = "官方卸载流程和全局 CLI 移除已完成。"
            logText += "\n[Clawbar] OpenClaw 卸载完成。\n"
        case let .failure(error):
            statusText = "OpenClaw 卸载失败。"
            detailText = error.localizedDescription
            logText += "\n[Clawbar] \(error.localizedDescription)\n"
            refreshInstallationStatus(force: true)
        }
    }

    private nonisolated static func operationName(for command: String) -> String {
        if command == uninstallCommand {
            return OpenClawOperation.uninstall.actionName
        }
        return OpenClawOperation.install.actionName
    }
}

private func sanitizeOutput(_ data: Data) -> String {
    let raw = String(decoding: data, as: UTF8.self)
    let pattern = #"\u{001B}\[[0-9;?]*[ -/]*[@-~]"#

    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return raw
    }

    let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
    return regex.stringByReplacingMatches(in: raw, options: [], range: range, withTemplate: "")
}
