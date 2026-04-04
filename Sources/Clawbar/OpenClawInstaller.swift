import Foundation

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
    case installationFailed(status: Int32, logURL: URL)
    case launchFailed(underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case let .installationFailed(status, logURL):
            "OpenClaw 安装失败，退出码 \(status)。日志位置：\(logURL.path)"
        case let .launchFailed(underlyingError):
            "无法启动 OpenClaw 安装：\(underlyingError.localizedDescription)"
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
    nonisolated static let wechatCapabilityInstallCommand = "npx -y @tencent-weixin/openclaw-weixin-cli@latest install"
    nonisolated static let detectCommand = "command -v openclaw"
    nonisolated static let statusCommand = "openclaw status"

    @Published private(set) var isInstalling = false
    @Published private(set) var isInstalled = false
    @Published private(set) var isRefreshingStatus = false
    @Published private(set) var statusText = "准备安装 OpenClaw。"
    @Published private(set) var detailText = "点击按钮后会执行官方安装脚本，但不会进入 onboarding。"
    @Published private(set) var installedBinaryPath: String?
    @Published private(set) var statusExcerpt: String?
    @Published private(set) var logText = ""
    @Published private(set) var lastLogURL = OpenClawInstaller.defaultLogURL()
    @Published private(set) var lastStatusRefreshDate: Date?

    private var activeProcess: Process?
    private var outputHandle: FileHandle?
    private let refreshInterval: TimeInterval
    private let nowProvider: @Sendable () -> Date
    private let overrideState: OpenClawInstallerOverride?
    private var refreshTimer: Timer?

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

                guard !self.isInstalling else { return }

                if let snapshot {
                    self.statusText = snapshot.title
                    self.detailText = snapshot.detail
                } else {
                    self.statusText = "准备安装 OpenClaw。"
                    self.detailText = "点击按钮后会执行官方安装脚本，但不会进入 onboarding。"
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
            if !isInstalling {
                statusText = "准备安装 OpenClaw。"
                detailText = "点击按钮后会执行官方安装脚本，但不会进入 onboarding。"
            }
        case let .installed(snapshot):
            isInstalled = true
            installedBinaryPath = snapshot.binaryPath
            statusExcerpt = snapshot.excerpt
            if !isInstalling {
                statusText = snapshot.title
                detailText = snapshot.detail
            }
        }
    }

    func startInstallIfNeeded() {
        if isInstalling {
            statusText = "OpenClaw 正在安装中。"
            detailText = "进度窗口会持续显示实时输出。"
            return
        }

        let logURL = Self.defaultLogURL()
        lastLogURL = logURL
        logText = "$ \(Self.installCommand)\n\n"
        statusText = "正在启动 OpenClaw 安装..."
        detailText = "这会执行官方安装脚本，并把输出实时写入日志窗口。"

        do {
            let process = try Self.makeProcess(
                logURL: logURL,
                environment: Self.installationEnvironment(base: ProcessInfo.processInfo.environment),
                outputHandler: { [weak self] chunk in
                    Task { @MainActor in
                        guard let self else { return }
                        self.appendLog(chunk)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor in
                        guard let self else { return }
                        self.finishInstall(with: result, logURL: logURL)
                    }
                }
            )

            try process.run()
            activeProcess = process
            isInstalling = true
            statusText = "正在安装 OpenClaw..."
            detailText = "官方脚本没有稳定的百分比接口，所以这里显示实时输出和当前状态。"
        } catch {
            finishInstall(with: .failure(OpenClawInstallerError.launchFailed(underlyingError: error)), logURL: logURL)
        }
    }

    nonisolated static func defaultLogURL() -> URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library")
        return libraryURL
            .appending(path: "Logs")
            .appending(path: "Clawbar")
            .appending(path: "openclaw-install.log")
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

    nonisolated static func didWeChatCapabilityInstallSucceed(
        exitStatus: Int32,
        output: String
    ) -> Bool {
        guard exitStatus == 0 else { return false }

        let normalizedOutput = output.lowercased()
        return !normalizedOutput.contains("error") && !normalizedOutput.contains("failed")
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
        process.arguments = ["-lc", installCommand]
        process.environment = environment
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { process in
            outputPipe.fileHandleForReading.readabilityHandler = nil
            try? outputHandle.close()

            if process.terminationStatus == 0 {
                completion(.success(()))
            } else {
                completion(.failure(OpenClawInstallerError.installationFailed(status: process.terminationStatus, logURL: logURL)))
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

    private func finishInstall(with result: Result<Void, Error>, logURL: URL) {
        activeProcess = nil
        outputHandle = nil
        lastLogURL = logURL

        switch result {
        case .success:
            let environment = Self.installationEnvironment(base: ProcessInfo.processInfo.environment)
            let openClawPath = Self.detectInstalledBinaryPath(environment: environment)
            let npxPath = Self.detectCommandPath("command -v npx", environment: environment)

            guard openClawPath != nil else {
                isInstalling = false
                statusText = "OpenClaw 安装完成。"
                detailText = "安装脚本执行结束，但尚未检测到全局 openclaw 命令。"
                logText += "\n[Clawbar] OpenClaw 安装完成，但未检测到全局 openclaw 命令。\n"
                refreshInstallationStatus(force: true)
                return
            }

            guard npxPath != nil else {
                isInstalling = false
                statusText = "OpenClaw 安装完成。"
                detailText = "安装脚本执行结束；未检测到 npx，已跳过微信能力自动安装。"
                logText += "\n[Clawbar] 未检测到 npx，已跳过微信能力自动安装。\n"
                refreshInstallationStatus(force: true)
                return
            }

            statusText = "OpenClaw 安装完成，正在安装微信能力..."
            detailText = "主安装已结束，Clawbar 正在补装官方 WeixinClawBot 插件。"
            logText += "\n[Clawbar] OpenClaw 安装完成，开始自动安装微信能力。\n"
            runPostInstallWeChatCapability(environment: environment)
        case let .failure(error):
            isInstalling = false
            statusText = "OpenClaw 安装失败。"
            detailText = error.localizedDescription
            logText += "\n[Clawbar] \(error.localizedDescription)\n"
        }
    }

    private func runPostInstallWeChatCapability(environment: [String: String]) {
        let command = Self.wechatCapabilityInstallCommand
        logText += "$ \(command)\n\n"

        Task.detached(priority: .utility) {
            let result = Self.runCommand(command, environment: environment, timeout: 300)

            await MainActor.run {
                self.isInstalling = false
                self.logText += result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "(no output)"
                    : result.output

                if result.timedOut {
                    self.statusText = "OpenClaw 安装完成。"
                    self.detailText = "微信能力自动安装超时；稍后仍可在 Channels 页单独安装。"
                    self.logText += "\n[Clawbar] 微信能力自动安装超时。\n"
                } else {
                    if !Self.didWeChatCapabilityInstallSucceed(
                        exitStatus: result.exitStatus,
                        output: result.output
                    ) {
                        self.statusText = "OpenClaw 安装完成。"
                        self.detailText = "微信能力自动安装可能失败；稍后可在 Channels 页重试。"
                        self.logText += "\n[Clawbar] 微信能力自动安装返回了失败信号，请检查上方日志。\n"
                    } else {
                        self.statusText = "OpenClaw 和微信能力已安装。"
                        self.detailText = "下一步可以直接去 Channels 页开始绑定微信。"
                        self.logText += "\n[Clawbar] 微信能力自动安装完成。\n"
                    }
                }

                self.refreshInstallationStatus(force: true)
            }
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
