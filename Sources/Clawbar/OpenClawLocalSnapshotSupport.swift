import Foundation

enum OpenClawLocalSnapshotSupport {
    private struct GatewayProcessMatch: Equatable, Sendable {
        let pid: Int?
    }

    static func providerSnapshot(
        binaryPath: String,
        configFileURL: URL = defaultConfigFileURL()
    ) -> OpenClawProviderSnapshot? {
        guard let config = loadConfigDictionary(configFileURL: configFileURL) else { return nil }

        let defaultModelRef = stringValue(at: "agents.defaults.model.primary", in: config)
            ?? stringValue(at: "agents.defaults.model", in: config)
        let providerEntries = dictionaryValue(at: "models.providers", in: config) ?? [:]
        let authProfiles = dictionaryValue(at: "auth.profiles", in: config) ?? [:]

        var providerIDs = Set(providerEntries.keys)
        var authStates: [String: OpenClawProviderAuthState] = [:]

        for profile in authProfiles.values {
            guard
                let payload = profile as? [String: Any],
                let providerID = trimmedNonEmpty(payload["provider"] as? String)
            else {
                continue
            }

            providerIDs.insert(providerID)

            let mode = trimmedNonEmpty(payload["mode"] as? String) ?? "configured"
            authStates[providerID] = OpenClawProviderAuthState(
                kind: mode,
                detail: authDetail(for: mode),
                source: "openclaw.json"
            )
        }

        for providerID in providerIDs where authStates[providerID] == nil {
            let providerPayload = providerEntries[providerID] as? [String: Any]
            let configured = providerPayload.map(hasConfiguredProviderPayload(_:)) ?? false
            authStates[providerID] = OpenClawProviderAuthState(
                kind: configured ? "configured" : "missing",
                detail: configured ? "在 openclaw.json 中检测到 provider 配置" : "missing",
                source: configured ? "openclaw.json" : nil
            )
        }

        guard defaultModelRef != nil || !authStates.isEmpty else { return nil }

        return OpenClawProviderSnapshot(
            binaryPath: binaryPath,
            configPath: configFileURL.path,
            defaultModelRef: defaultModelRef,
            authStates: authStates
        )
    }

    static func channelsSnapshot(
        configFileURL: URL = defaultConfigFileURL()
    ) -> OpenClawChannelsSnapshot? {
        guard
            let config = loadConfigDictionary(configFileURL: configFileURL),
            let channels = dictionaryValue(at: "channels", in: config),
            !channels.isEmpty
        else {
            return nil
        }

        var orderedChannelIDs: [String] = []
        var channelsByID: [String: OpenClawChannelSnapshot] = [:]

        for channelID in channels.keys.sorted() {
            guard let payload = channels[channelID] as? [String: Any] else { continue }

            let enabled = payload["enabled"] as? Bool ?? false
            let appID = trimmedNonEmpty(payload["appId"] as? String)
                ?? trimmedNonEmpty(payload["clientId"] as? String)
            let brand = trimmedNonEmpty(payload["domain"] as? String)
            let configured = enabled || appID != nil || !payload.isEmpty
            let accountID = appID ?? channelID

            let accounts: [OpenClawChannelAccountSnapshot]
            if configured {
                accounts = [
                    OpenClawChannelAccountSnapshot(
                        accountID: accountID,
                        enabled: enabled,
                        configured: configured,
                        running: false,
                        appID: appID,
                        brand: brand,
                        lastError: nil
                    )
                ]
            } else {
                accounts = []
            }

            orderedChannelIDs.append(channelID)
            channelsByID[channelID] = OpenClawChannelSnapshot(
                id: channelID,
                label: channelLabel(for: channelID, brand: brand),
                detailLabel: brand,
                exists: true,
                configured: configured,
                running: false,
                lastError: enabled ? "CLI 状态命令超时，当前仅基于本地配置推断。" : nil,
                defaultAccountID: configured ? accountID : nil,
                accounts: accounts
            )
        }

        guard !channelsByID.isEmpty else { return nil }

        return OpenClawChannelsSnapshot(
            orderedChannelIDs: orderedChannelIDs,
            channelsByID: channelsByID,
            statusLoaded: true,
            listLoaded: false,
            statusFailureDetail: "openclaw channels status/list --json 未返回结果；已回退到 openclaw.json。",
            listFailureDetail: nil,
            pluginInspections: [:]
        )
    }

    static func gatewaySnapshot(
        binaryPath: String,
        configFileURL: URL = defaultConfigFileURL(),
        processListProvider: @Sendable () -> String = defaultProcessList
    ) -> OpenClawGatewayStatusSnapshot? {
        guard let config = loadConfigDictionary(configFileURL: configFileURL) else { return nil }

        let gatewayMode = stringValue(at: "gateway.mode", in: config)
        let hasGatewayConfig = dictionaryValue(at: "gateway", in: config) != nil
        guard hasGatewayConfig || gatewayMode != nil else { return nil }

        let displayPath = OpenClawInstaller.displayBinaryPath(binaryPath)
        let processMatch = findGatewayProcess(in: processListProvider())

        if gatewayMode == "local" {
            if let processMatch {
                return OpenClawGatewayStatusSnapshot(
                    state: .running,
                    detail: "gateway status 命令超时；基于本地进程推断 Gateway 仍在运行。",
                    binaryPath: displayPath,
                    runtimeStatus: "running",
                    serviceLoaded: true,
                    serviceLabel: nil,
                    pid: processMatch.pid,
                    missingUnit: false
                )
            }

            return OpenClawGatewayStatusSnapshot(
                state: .stopped,
                detail: "gateway status 命令超时；检测到本地 Gateway 配置，但未发现运行中的 gateway 进程。",
                binaryPath: displayPath,
                runtimeStatus: "stopped",
                serviceLoaded: false,
                serviceLabel: nil,
                pid: nil,
                missingUnit: false
            )
        }

        return OpenClawGatewayStatusSnapshot(
            state: .unknown,
            detail: "gateway status 命令超时；当前 Gateway 模式为 \(gatewayMode ?? "未知")，已回退到本地配置推断。",
            binaryPath: displayPath,
            runtimeStatus: nil,
            serviceLoaded: false,
            serviceLabel: nil,
            pid: nil,
            missingUnit: false
        )
    }

    static func stringValue(at path: String, configFileURL: URL = defaultConfigFileURL()) -> String? {
        guard let config = loadConfigDictionary(configFileURL: configFileURL) else { return nil }
        return stringValue(at: path, in: config)
    }

    static func hasValue(at path: String, configFileURL: URL = defaultConfigFileURL()) -> Bool {
        guard let config = loadConfigDictionary(configFileURL: configFileURL) else { return false }
        return value(at: path, in: config) != nil
    }

    static func defaultConfigFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".openclaw")
            .appending(path: "openclaw.json")
    }

    private static func loadConfigDictionary(configFileURL: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: configFileURL) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func stringValue(at path: String, in dictionary: [String: Any]) -> String? {
        value(at: path, in: dictionary) as? String
    }

    private static func dictionaryValue(at path: String, in dictionary: [String: Any]) -> [String: Any]? {
        value(at: path, in: dictionary) as? [String: Any]
    }

    private static func value(at path: String, in dictionary: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        guard !components.isEmpty else { return nil }

        var current: Any = dictionary
        for component in components {
            guard let nested = current as? [String: Any] else {
                return nil
            }
            current = nested[component] as Any
        }

        return current
    }

    private static func hasConfiguredProviderPayload(_ payload: [String: Any]) -> Bool {
        if trimmedNonEmpty(payload["apiKey"] as? String) != nil {
            return true
        }
        if trimmedNonEmpty(payload["baseUrl"] as? String) != nil {
            return true
        }
        if let models = payload["models"] as? [[String: Any]], !models.isEmpty {
            return true
        }
        return false
    }

    private static func authDetail(for mode: String) -> String {
        switch mode {
        case "oauth":
            "在 openclaw.json 中检测到 OAuth 认证"
        case "api_key":
            "在 openclaw.json 中检测到 API Key 认证"
        default:
            "在 openclaw.json 中检测到认证配置"
        }
    }

    private static func channelLabel(for channelID: String, brand: String?) -> String {
        switch channelID {
        case "feishu":
            return "Feishu"
        case "openclaw-weixin":
            return "WeChat"
        default:
            return trimmedNonEmpty(brand)?.capitalized ?? channelID
        }
    }

    private static func defaultProcessList() -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm=,args="]
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
        } catch {
            return ""
        }

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func findGatewayProcess(in processList: String) -> GatewayProcessMatch? {
        for rawLine in processList.split(separator: "\n") {
            let line = String(rawLine)
            guard
                line.contains("openclaw-gateway")
                    || (line.contains("/openclaw") && line.contains(" gateway"))
                    || line.contains("dist/entry.js gateway")
            else {
                continue
            }

            let pid = line
                .split(whereSeparator: \.isWhitespace)
                .first
                .flatMap { Int($0) }
            return GatewayProcessMatch(pid: pid)
        }

        return nil
    }
}
