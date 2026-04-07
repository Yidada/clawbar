import Foundation

struct OpenClawChannelAccountSnapshot: Equatable, Sendable {
    let accountID: String
    let enabled: Bool
    let configured: Bool
    let running: Bool
    let appID: String?
    let brand: String?
    let lastError: String?

    var displayLabel: String {
        if let appID = trimmedNonEmpty(appID) {
            if let brand = trimmedNonEmpty(brand) {
                return "\(appID) (\(brand))"
            }
            return appID
        }

        return accountID
    }
}

struct OpenClawChannelSnapshot: Equatable, Sendable {
    let id: String
    let label: String
    let detailLabel: String?
    let exists: Bool
    let configured: Bool
    let running: Bool
    let lastError: String?
    let defaultAccountID: String?
    let accounts: [OpenClawChannelAccountSnapshot]

    var primaryAccount: OpenClawChannelAccountSnapshot? {
        if let defaultAccountID,
           let defaultAccount = accounts.first(where: { $0.accountID == defaultAccountID }) {
            return defaultAccount
        }

        if let configuredAccount = accounts.first(where: { $0.configured }) {
            return configuredAccount
        }

        return accounts.first
    }
}

struct OpenClawPluginInspectionSnapshot: Equatable, Sendable {
    let pluginID: String
    let exists: Bool
    let enabled: Bool
    let activated: Bool
    let status: String?
    let channelIDs: [String]
    let failureDetail: String?

    var isActive: Bool {
        exists && enabled && activated
    }
}

struct OpenClawChannelsSnapshot: Equatable, Sendable {
    let orderedChannelIDs: [String]
    let channelsByID: [String: OpenClawChannelSnapshot]
    let statusLoaded: Bool
    let listLoaded: Bool
    let statusFailureDetail: String?
    let listFailureDetail: String?
    let pluginInspections: [String: OpenClawPluginInspectionSnapshot]

    var hasUsableChannelData: Bool {
        statusLoaded || listLoaded
    }

    func channel(id: String) -> OpenClawChannelSnapshot? {
        channelsByID[id]
    }

    func pluginInspection(id: String) -> OpenClawPluginInspectionSnapshot? {
        pluginInspections[id]
    }
}

enum OpenClawChannelsSnapshotSupport {
    typealias CommandRunner = ChannelCommandSupport.CommandRunner

    private struct StatusPayload {
        let orderedChannelIDs: [String]
        let channelsByID: [String: OpenClawChannelSnapshot]
    }

    private struct ListPayload {
        let accountIDsByChannelID: [String: [String]]
    }

    static let statusArguments = ["channels", "status", "--json"]
    static let listArguments = ["channels", "list", "--json"]

    static func fetchSnapshot(
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner,
        pluginIDs: [String] = []
    ) -> OpenClawChannelsSnapshot {
        let statusResult = runCommand(openClawBinaryPath, statusArguments, environment, 12)
        let listResult = runCommand(openClawBinaryPath, listArguments, environment, 8)

        let statusPayload = parseStatusPayloadInternal(from: statusResult.output)
        let listPayload = parseListPayloadInternal(from: listResult.output)

        let statusLoaded = !statusResult.timedOut && statusResult.exitStatus == 0 && statusPayload != nil
        let listLoaded = !listResult.timedOut && listResult.exitStatus == 0 && listPayload != nil

        var orderedChannelIDs = statusPayload?.orderedChannelIDs ?? []
        var channelsByID = statusPayload?.channelsByID ?? [:]

        if let listPayload {
            mergeListPayload(listPayload, into: &channelsByID, orderedChannelIDs: &orderedChannelIDs)
        }

        let pluginInspections = Dictionary(uniqueKeysWithValues: pluginIDs.map { pluginID in
            (
                pluginID,
                inspectPlugin(
                    pluginID: pluginID,
                    openClawBinaryPath: openClawBinaryPath,
                    environment: environment,
                    runCommand: runCommand
                )
            )
        })

        if !statusLoaded, !listLoaded,
           let fallback = OpenClawLocalSnapshotSupport.channelsSnapshot() {
            return OpenClawChannelsSnapshot(
                orderedChannelIDs: fallback.orderedChannelIDs,
                channelsByID: fallback.channelsByID,
                statusLoaded: fallback.statusLoaded,
                listLoaded: fallback.listLoaded,
                statusFailureDetail: commandFailureDetail(
                    result: statusResult,
                    fallbackCommand: "openclaw channels status --json"
                ),
                listFailureDetail: commandFailureDetail(
                    result: listResult,
                    fallbackCommand: "openclaw channels list --json"
                ),
                pluginInspections: pluginInspections
            )
        }

        return OpenClawChannelsSnapshot(
            orderedChannelIDs: orderedChannelIDs,
            channelsByID: channelsByID,
            statusLoaded: statusLoaded,
            listLoaded: listLoaded,
            statusFailureDetail: statusLoaded ? nil : commandFailureDetail(
                result: statusResult,
                fallbackCommand: "openclaw channels status --json"
            ),
            listFailureDetail: listLoaded ? nil : commandFailureDetail(
                result: listResult,
                fallbackCommand: "openclaw channels list --json"
            ),
            pluginInspections: pluginInspections
        )
    }

    static func parseStatusPayload(from output: String) -> OpenClawChannelsSnapshot? {
        guard let parsed = parseStatusPayloadInternal(from: output) else { return nil }
        return OpenClawChannelsSnapshot(
            orderedChannelIDs: parsed.orderedChannelIDs,
            channelsByID: parsed.channelsByID,
            statusLoaded: true,
            listLoaded: false,
            statusFailureDetail: nil,
            listFailureDetail: nil,
            pluginInspections: [:]
        )
    }

    static func parseListPayload(from output: String) -> OpenClawChannelsSnapshot? {
        guard let parsed = parseListPayloadInternal(from: output) else { return nil }

        var orderedChannelIDs: [String] = []
        var channelsByID: [String: OpenClawChannelSnapshot] = [:]
        mergeListPayload(parsed, into: &channelsByID, orderedChannelIDs: &orderedChannelIDs)

        return OpenClawChannelsSnapshot(
            orderedChannelIDs: orderedChannelIDs,
            channelsByID: channelsByID,
            statusLoaded: false,
            listLoaded: true,
            statusFailureDetail: nil,
            listFailureDetail: nil,
            pluginInspections: [:]
        )
    }

    static func parsePluginInspection(
        pluginID: String,
        from output: String
    ) -> OpenClawPluginInspectionSnapshot? {
        guard let payload = parseJSONObject(from: output) else { return nil }
        return makePluginInspection(pluginID: pluginID, payload: payload)
    }

    private static func parseStatusPayloadInternal(from output: String) -> StatusPayload? {
        guard let payload = parseJSONObject(from: output) else { return nil }

        let labels = payload["channelLabels"] as? [String: String] ?? [:]
        let detailLabels = payload["channelDetailLabels"] as? [String: String] ?? [:]
        let channelStates = payload["channels"] as? [String: [String: Any]] ?? [:]
        let channelAccounts = payload["channelAccounts"] as? [String: [[String: Any]]] ?? [:]
        let defaultAccountIDs = payload["channelDefaultAccountId"] as? [String: String] ?? [:]
        let channelMeta = payload["channelMeta"] as? [[String: Any]] ?? []

        var metaByID: [String: [String: Any]] = [:]
        for entry in channelMeta {
            guard let id = trimmedNonEmpty(entry["id"] as? String) else { continue }
            metaByID[id] = entry
        }

        var orderedChannelIDs: [String] = []
        let preferredOrder = payload["channelOrder"] as? [String] ?? []
        for channelID in preferredOrder where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }

        for channelID in labels.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }
        for channelID in detailLabels.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }
        for channelID in channelStates.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }
        for channelID in channelAccounts.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }
        for channelID in defaultAccountIDs.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }
        for channelID in metaByID.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }

        let channelsByID = Dictionary(uniqueKeysWithValues: orderedChannelIDs.map { channelID in
            let channelState = channelStates[channelID]
            let accounts = (channelAccounts[channelID] ?? []).compactMap(parseAccount(payload:))
            let configured = (channelState?["configured"] as? Bool) ?? accounts.contains(where: \.configured)
            let running = (channelState?["running"] as? Bool) ?? accounts.contains(where: \.running)
            let lastError = trimmedNonEmpty(channelState?["lastError"] as? String)
                ?? accounts.compactMap(\.lastError).first
            let defaultAccountID = trimmedNonEmpty(defaultAccountIDs[channelID])
            let meta = metaByID[channelID]
            let label = trimmedNonEmpty(meta?["label"] as? String)
                ?? trimmedNonEmpty(labels[channelID])
                ?? channelID
            let detailLabel = trimmedNonEmpty(meta?["detailLabel"] as? String)
                ?? trimmedNonEmpty(detailLabels[channelID])

            return (
                channelID,
                OpenClawChannelSnapshot(
                    id: channelID,
                    label: label,
                    detailLabel: detailLabel,
                    exists: true,
                    configured: configured,
                    running: running,
                    lastError: lastError,
                    defaultAccountID: defaultAccountID,
                    accounts: accounts
                )
            )
        })

        return StatusPayload(
            orderedChannelIDs: orderedChannelIDs,
            channelsByID: channelsByID
        )
    }

    private static func parseListPayloadInternal(from output: String) -> ListPayload? {
        guard let payload = parseJSONObject(from: output),
              let chat = payload["chat"] as? [String: Any] else {
            return nil
        }

        let accountIDsByChannelID = chat.reduce(into: [String: [String]]()) { partialResult, entry in
            let values = stringArray(from: entry.value)
            if !values.isEmpty {
                partialResult[entry.key] = values
            }
        }

        return ListPayload(accountIDsByChannelID: accountIDsByChannelID)
    }

    private static func mergeListPayload(
        _ listPayload: ListPayload,
        into channelsByID: inout [String: OpenClawChannelSnapshot],
        orderedChannelIDs: inout [String]
    ) {
        for channelID in listPayload.accountIDsByChannelID.keys.sorted() where !orderedChannelIDs.contains(channelID) {
            orderedChannelIDs.append(channelID)
        }

        for (channelID, accountIDs) in listPayload.accountIDsByChannelID {
            let existing = channelsByID[channelID]
            var accountsByID = Dictionary(uniqueKeysWithValues: (existing?.accounts ?? []).map { ($0.accountID, $0) })

            for accountID in accountIDs {
                if let existingAccount = accountsByID[accountID] {
                    accountsByID[accountID] = OpenClawChannelAccountSnapshot(
                        accountID: existingAccount.accountID,
                        enabled: existingAccount.enabled,
                        configured: true,
                        running: existingAccount.running,
                        appID: existingAccount.appID,
                        brand: existingAccount.brand,
                        lastError: existingAccount.lastError
                    )
                } else {
                    accountsByID[accountID] = OpenClawChannelAccountSnapshot(
                        accountID: accountID,
                        enabled: true,
                        configured: true,
                        running: false,
                        appID: nil,
                        brand: nil,
                        lastError: nil
                    )
                }
            }

            let mergedAccounts = accountsByID.values.sorted { lhs, rhs in
                lhs.accountID.localizedStandardCompare(rhs.accountID) == .orderedAscending
            }

            let defaultAccountID = existing?.defaultAccountID
                ?? accountIDs.first
            let configured = existing?.configured == true || !accountIDs.isEmpty
            let running = existing?.running ?? false

            channelsByID[channelID] = OpenClawChannelSnapshot(
                id: channelID,
                label: existing?.label ?? channelID,
                detailLabel: existing?.detailLabel,
                exists: existing?.exists ?? true,
                configured: configured,
                running: running,
                lastError: existing?.lastError,
                defaultAccountID: defaultAccountID,
                accounts: mergedAccounts
            )
        }
    }

    private static func inspectPlugin(
        pluginID: String,
        openClawBinaryPath: String,
        environment: [String: String],
        runCommand: CommandRunner
    ) -> OpenClawPluginInspectionSnapshot {
        let result = runCommand(
            openClawBinaryPath,
            ["plugins", "inspect", pluginID, "--json"],
            environment,
            8
        )

        if result.timedOut {
            return OpenClawPluginInspectionSnapshot(
                pluginID: pluginID,
                exists: false,
                enabled: false,
                activated: false,
                status: nil,
                channelIDs: [],
                failureDetail: "openclaw plugins inspect \(pluginID) --json 未在 8 秒内完成。"
            )
        }

        guard result.exitStatus == 0 else {
            return OpenClawPluginInspectionSnapshot(
                pluginID: pluginID,
                exists: false,
                enabled: false,
                activated: false,
                status: nil,
                channelIDs: [],
                failureDetail: ChannelCommandSupport.extractFailureDetail(from: result.output)
                    ?? "openclaw plugins inspect \(pluginID) --json 退出码 \(result.exitStatus)。"
            )
        }

        guard let payload = parseJSONObject(from: result.output) else {
            return OpenClawPluginInspectionSnapshot(
                pluginID: pluginID,
                exists: false,
                enabled: false,
                activated: false,
                status: nil,
                channelIDs: [],
                failureDetail: "未能从 openclaw plugins inspect \(pluginID) --json 的输出中提取有效 JSON。"
            )
        }

        return makePluginInspection(pluginID: pluginID, payload: payload)
    }

    private static func makePluginInspection(
        pluginID: String,
        payload: [String: Any]
    ) -> OpenClawPluginInspectionSnapshot {
        let pluginPayload = (payload["plugin"] as? [String: Any]) ?? payload

        return OpenClawPluginInspectionSnapshot(
            pluginID: trimmedNonEmpty(pluginPayload["id"] as? String) ?? pluginID,
            exists: true,
            enabled: pluginPayload["enabled"] as? Bool ?? false,
            activated: pluginPayload["activated"] as? Bool ?? false,
            status: trimmedNonEmpty(pluginPayload["status"] as? String),
            channelIDs: stringArray(from: pluginPayload["channelIds"]),
            failureDetail: nil
        )
    }

    private static func parseAccount(payload: [String: Any]) -> OpenClawChannelAccountSnapshot? {
        guard let accountID = trimmedNonEmpty(payload["accountId"] as? String) else {
            return nil
        }

        return OpenClawChannelAccountSnapshot(
            accountID: accountID,
            enabled: payload["enabled"] as? Bool ?? false,
            configured: payload["configured"] as? Bool ?? false,
            running: payload["running"] as? Bool ?? false,
            appID: trimmedNonEmpty(payload["appId"] as? String),
            brand: trimmedNonEmpty(payload["brand"] as? String),
            lastError: trimmedNonEmpty(payload["lastError"] as? String)
        )
    }

    private static func stringArray(from value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { trimmedNonEmpty($0 as? String) }
    }

    private static func parseJSONObject(from output: String) -> [String: Any]? {
        let jsonString = ChannelCommandSupport.extractTrailingJSONObjectString(from: output) ?? output
        return ChannelCommandSupport.parseJSONObject(from: jsonString)
    }

    private static func commandFailureDetail(
        result: OpenClawChannelCommandResult,
        fallbackCommand: String
    ) -> String {
        if result.timedOut {
            return "\(fallbackCommand) 未在规定时间内完成。"
        }

        return ChannelCommandSupport.extractFailureDetail(from: result.output)
            ?? "\(fallbackCommand) 退出码 \(result.exitStatus)。"
    }
}
