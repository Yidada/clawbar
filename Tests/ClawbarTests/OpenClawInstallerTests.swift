import XCTest
@testable import Clawbar

@MainActor
final class OpenClawInstallerTests: XCTestCase {
    private final class AttemptRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var environments: [[String: String]] = []
        private var attempts = 0

        func record(environment: [String: String]) -> Int {
            lock.lock()
            defer { lock.unlock() }
            environments.append(environment)
            attempts += 1
            return attempts
        }

        func snapshot() -> [[String: String]] {
            lock.lock()
            defer { lock.unlock() }
            return environments
        }
    }

    func testInstallCommandMatchesOfficialNoOnboardFlow() {
        XCTAssertEqual(
            OpenClawInstaller.installCommand,
            "curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard"
        )
    }

    func testUninstallCommandMatchesNonInteractiveFullRemovalFlow() {
        XCTAssertEqual(
            OpenClawInstaller.uninstallCommand,
            "openclaw uninstall --all --yes --non-interactive && npm rm -g openclaw"
        )
    }

    func testUpdateCommandMatchesOfficialCurrentChannelFlow() {
        XCTAssertEqual(
            OpenClawInstaller.updateCommand,
            "openclaw update --yes"
        )
    }

    func testDefaultRefreshIntervalIsFiveMinutes() {
        XCTAssertEqual(OpenClawInstaller.defaultRefreshInterval, 300)
    }

    func testParseDetectedBinaryPathReturnsTrimmedCommandPath() {
        XCTAssertEqual(
            OpenClawInstaller.parseDetectedBinaryPath("/opt/homebrew/bin/openclaw\n"),
            "/opt/homebrew/bin/openclaw"
        )
    }

    func testParseDetectedBinaryPathReturnsNilForEmptyOutput() {
        XCTAssertNil(OpenClawInstaller.parseDetectedBinaryPath("\n  \n"))
    }

    func testDisplayBinaryPathCollapsesHomePrefix() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            OpenClawInstaller.displayBinaryPath("\(homePath)/bin/openclaw"),
            "~/bin/openclaw"
        )
    }

    func testSummarizeStatusLineCompressesPluginWarning() {
        XCTAssertEqual(
            OpenClawInstaller.summarizeStatusLine("[plugins] plugins.allow is empty; discovered non-bundled plugins may auto-load: foo, bar"),
            "plugins.allow is empty; discovered non-bundled plugins."
        )
    }

    func testSummarizeStatusLineTruncatesLongGenericOutput() {
        let summary = OpenClawInstaller.summarizeStatusLine(String(repeating: "a", count: 120), maxLength: 20)
        XCTAssertEqual(summary, String(repeating: "a", count: 19) + "…")
    }

    func testShouldRefreshStatusReturnsTrueWithoutCache() {
        XCTAssertTrue(
            OpenClawInstaller.shouldRefreshStatus(
                force: false,
                isRefreshing: false,
                lastRefreshDate: nil,
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsFalseWhenCacheIsFresh() {
        XCTAssertFalse(
            OpenClawInstaller.shouldRefreshStatus(
                force: false,
                isRefreshing: false,
                lastRefreshDate: Date(timeIntervalSince1970: 90),
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsTrueWhenForced() {
        XCTAssertTrue(
            OpenClawInstaller.shouldRefreshStatus(
                force: true,
                isRefreshing: false,
                lastRefreshDate: Date(timeIntervalSince1970: 99),
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testShouldRefreshStatusReturnsFalseWhileRefreshIsInFlight() {
        XCTAssertFalse(
            OpenClawInstaller.shouldRefreshStatus(
                force: true,
                isRefreshing: true,
                lastRefreshDate: nil,
                now: Date(timeIntervalSince1970: 100),
                refreshInterval: 30
            )
        )
    }

    func testInstallRetryFallbackRegistryDefaultsToByteDanceMirror() {
        XCTAssertEqual(
            OpenClawInstaller.installRetryFallbackRegistry(base: [:]),
            "https://bnpm.byted.org"
        )
    }

    func testInstallRetryFallbackRegistrySupportsDisableFlag() {
        XCTAssertNil(
            OpenClawInstaller.installRetryFallbackRegistry(base: [
                "OPENCLAW_NPM_REGISTRY_FALLBACK": "false"
            ])
        )
    }

    func testShouldRetryInstallWithFallbackMatchesNetworkFailuresOnly() {
        XCTAssertTrue(
            OpenClawInstaller.shouldRetryInstallWithFallback(
                logText: "npm ERR! code ETIMEDOUT\nnpm ERR! network request failed"
            )
        )
        XCTAssertFalse(
            OpenClawInstaller.shouldRetryInstallWithFallback(
                logText: "npm ERR! code EEXIST\nnpm ERR! path /opt/homebrew/bin/openclaw"
            )
        )
    }

    func testParseStatusPayloadReadsRuntimeAndGatewayOverview() {
        let output = """
        [plugins] warning
        {
          "runtimeVersion": "2026.4.5",
          "gateway": {
            "reachable": true,
            "url": "ws://127.0.0.1:18789"
          },
          "gatewayService": {
            "installed": true,
            "loaded": true,
            "runtimeShort": "running (pid 123)"
          }
        }
        """

        let payload = OpenClawInstaller.parseStatusPayload(from: output)

        XCTAssertEqual(payload?.runtimeVersion, "2026.4.5")
        XCTAssertEqual(payload?.gateway.reachable, true)
        XCTAssertEqual(payload?.gateway.url, "ws://127.0.0.1:18789")
        XCTAssertEqual(payload?.gatewayService.runtimeShort, "running (pid 123)")
    }

    func testParseUpdateStatusPayloadReadsAvailabilityVersionAndChannel() {
        let output = """
        {
          "update": {
            "registry": {
              "latestVersion": "2026.4.2"
            }
          },
          "channel": {
            "label": "stable (default)"
          },
          "availability": {
            "available": true,
            "latestVersion": "2026.4.2"
          }
        }
        """

        let payload = OpenClawInstaller.parseUpdateStatusPayload(from: output)

        XCTAssertEqual(payload?.isUpdateAvailable, true)
        XCTAssertEqual(payload?.latestVersion, "2026.4.2")
        XCTAssertEqual(payload?.channelLabel, "stable (default)")
    }

    func testStartInstallRetriesWithFallbackRegistryWhenLogLooksNetworkRelated() async {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let primaryEnvironment = ProcessInfo.processInfo.environment
        let fallbackRegistry = "https://bnpm.byted.org"
        setenv("OPENCLAW_NPM_REGISTRY_FALLBACK", fallbackRegistry, 1)
        defer {
            if let previous = primaryEnvironment["OPENCLAW_NPM_REGISTRY_FALLBACK"] {
                setenv("OPENCLAW_NPM_REGISTRY_FALLBACK", previous, 1)
            } else {
                unsetenv("OPENCLAW_NPM_REGISTRY_FALLBACK")
            }
        }

        let recorder = AttemptRecorder()

        let installer = OpenClawInstaller(
            autoStartTimer: false,
            processFactory: { _, logURL, environment, _, completion in
                let currentAttempt = recorder.record(environment: environment)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-lc", "sleep 0.01"]
                process.environment = environment
                process.currentDirectoryURL = tempDirectory
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { _ in
                    let logText: String
                    if currentAttempt == 1 {
                        logText = "npm ERR! code ETIMEDOUT\nnpm ERR! network request failed\n"
                    } else {
                        logText = "npm ERR! code EEXIST\nnpm ERR! path /opt/homebrew/bin/openclaw\n"
                    }
                    try? logText.write(to: logURL, atomically: true, encoding: .utf8)
                    completion(.failure(NSError(domain: "Test", code: currentAttempt)))
                }
                return process
            }
        )

        installer.startInstallIfNeeded()

        await waitForCondition(timeout: 2) { !installer.isInstalling }

        let capturedEnvironments = recorder.snapshot()
        XCTAssertEqual(capturedEnvironments.count, 2)
        XCTAssertNil(capturedEnvironments[0]["npm_config_registry"])
        XCTAssertEqual(capturedEnvironments[1]["npm_config_registry"], fallbackRegistry)
        XCTAssertEqual(capturedEnvironments[1]["OPENCLAW_NPM_REGISTRY"], fallbackRegistry)
        XCTAssertTrue(installer.logText.contains("将使用备用 registry 重试"))
        XCTAssertEqual(installer.statusText, "OpenClaw 安装失败。")
    }

    func testStartInstallDoesNotRetryForNonNetworkFailure() async {
        let primaryEnvironment = ProcessInfo.processInfo.environment
        setenv("OPENCLAW_NPM_REGISTRY_FALLBACK", "https://bnpm.byted.org", 1)
        defer {
            if let previous = primaryEnvironment["OPENCLAW_NPM_REGISTRY_FALLBACK"] {
                setenv("OPENCLAW_NPM_REGISTRY_FALLBACK", previous, 1)
            } else {
                unsetenv("OPENCLAW_NPM_REGISTRY_FALLBACK")
            }
        }

        let recorder = AttemptRecorder()

        let installer = OpenClawInstaller(
            autoStartTimer: false,
            processFactory: { _, logURL, environment, _, completion in
                _ = recorder.record(environment: environment)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-lc", "sleep 0.01"]
                process.environment = environment
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { _ in
                    try? "npm ERR! code EEXIST\nnpm ERR! path /opt/homebrew/bin/openclaw\n"
                        .write(to: logURL, atomically: true, encoding: .utf8)
                    completion(.failure(NSError(domain: "Test", code: 1)))
                }
                return process
            }
        )

        installer.startInstallIfNeeded()

        await waitForCondition(timeout: 2) { !installer.isInstalling }

        let capturedEnvironments = recorder.snapshot()
        XCTAssertEqual(capturedEnvironments.count, 1)
        XCTAssertFalse(installer.logText.contains("将使用备用 registry 重试"))
        XCTAssertEqual(installer.statusText, "OpenClaw 安装失败。")
    }

    func testMakeStatusSnapshotBuildsStructuredHealthOverview() {
        let statusResult = OpenClawChannelCommandResult(
            output: """
            {
              "runtimeVersion": "2026.4.5",
              "gateway": {
                "reachable": true
              },
              "gatewayService": {
                "installed": true,
                "loaded": true,
                "runtimeShort": "running"
              }
            }
            """,
            exitStatus: 0,
            timedOut: false
        )
        let providerSnapshot = OpenClawProviderSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            configPath: "/Users/test/.openclaw/openclaw.json",
            defaultModelRef: "openrouter/anthropic/claude-sonnet-4-6",
            authStates: [
                "openrouter": OpenClawProviderAuthState(
                    kind: "env",
                    detail: "OPENROUTER_API_KEY",
                    source: "env: OPENROUTER_API_KEY"
                )
            ]
        )
        let gatewaySnapshot = OpenClawGatewayStatusSnapshot(
            state: .running,
            detail: "Gateway 后台服务正在运行。",
            binaryPath: "/opt/homebrew/bin/openclaw",
            runtimeStatus: "running",
            serviceInstalled: true,
            serviceLoaded: true,
            serviceLabel: "ai.openclaw.gateway",
            pid: 123,
            missingUnit: false
        )
        let channelSnapshot = OpenClawChannelsSnapshot(
            orderedChannelIDs: ["wechat"],
            channelsByID: [
                "wechat": OpenClawChannelSnapshot(
                    id: "wechat",
                    label: "WeChat",
                    detailLabel: nil,
                    exists: true,
                    configured: true,
                    running: true,
                    lastError: nil,
                    defaultAccountID: "default",
                    accounts: [
                        OpenClawChannelAccountSnapshot(
                            accountID: "default",
                            enabled: true,
                            configured: true,
                            running: true,
                            appID: nil,
                            brand: nil,
                            lastError: nil
                        )
                    ]
                )
            ],
            statusLoaded: true,
            listLoaded: true,
            statusFailureDetail: nil,
            listFailureDetail: nil,
            pluginInspections: [:]
        )

        let snapshot = OpenClawInstaller.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            statusResult: statusResult,
            channelSnapshot: channelSnapshot,
            providerSnapshot: providerSnapshot,
            gatewaySnapshot: gatewaySnapshot
        )

        XCTAssertEqual(snapshot.title, "OpenClaw 已安装")
        XCTAssertEqual(snapshot.detail, "Provider 已配置 · Gateway 可达 · Channel 已就绪")
        XCTAssertEqual(snapshot.excerpt, "OpenClaw 2026.4.5")
        XCTAssertEqual(snapshot.healthSnapshot.overallLevel, .healthy)
        XCTAssertEqual(snapshot.healthSnapshot.dimensions.map(\.dimension), [.provider, .gateway, .channel])
        XCTAssertEqual(snapshot.healthSnapshot.dimensions[0].summary, "OpenRouter / anthropic/claude-sonnet-4-6")
        XCTAssertEqual(snapshot.healthSnapshot.dimensions[1].statusLabel, "可达")
        XCTAssertEqual(snapshot.healthSnapshot.dimensions[2].summary, "WeChat / 已就绪")
    }

    func testMakeStatusSnapshotReportsTimeoutAndKeepsPartialHealthView() {
        let gatewaySnapshot = OpenClawGatewayStatusSnapshot(
            state: .missing,
            detail: "Gateway 服务尚未安装到 launchd。",
            binaryPath: "/opt/homebrew/bin/openclaw",
            runtimeStatus: nil,
            serviceInstalled: false,
            serviceLoaded: false,
            serviceLabel: "ai.openclaw.gateway",
            pid: nil,
            missingUnit: true
        )
        let unavailableChannels = OpenClawChannelsSnapshot(
            orderedChannelIDs: [],
            channelsByID: [:],
            statusLoaded: false,
            listLoaded: false,
            statusFailureDetail: "openclaw channels status --json failed",
            listFailureDetail: "openclaw channels list --json failed",
            pluginInspections: [:]
        )

        let snapshot = OpenClawInstaller.makeStatusSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            statusResult: OpenClawChannelCommandResult(output: "", exitStatus: 0, timedOut: true),
            channelSnapshot: unavailableChannels,
            providerSnapshot: nil,
            gatewaySnapshot: gatewaySnapshot
        )

        XCTAssertEqual(snapshot.detail, "openclaw status --json 未在 30 秒内完成；当前展示最近一次可推断的健康视图。")
        XCTAssertEqual(snapshot.healthSnapshot.dimensions[1].statusLabel, "未安装")
        XCTAssertEqual(snapshot.healthSnapshot.dimensions[2].statusLabel, "未知")
    }

    func testInstallationSearchPathsAddsCommonUserPackageManagerDirectories() {
        let paths = OpenClawInstaller.installationSearchPaths(
            base: [:],
            homeDirectoryPath: "/Users/liuyuyang"
        )

        XCTAssertEqual(
            paths,
            [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
                "/Users/liuyuyang/.bun/bin",
                "/Users/liuyuyang/Library/pnpm",
                "/Users/liuyuyang/.npm-global/bin",
                "/Users/liuyuyang/.local/bin",
            ]
        )
    }

    func testInstallationSearchPathsHonorsPackageManagerEnvironmentOverridesAndDeduplicates() {
        let paths = OpenClawInstaller.installationSearchPaths(
            base: [
                "BUN_INSTALL": "/custom/bun",
                "PNPM_HOME": "/custom/pnpm",
                "npm_config_prefix": "/custom/npm",
                "PATH": "/custom/bin:/usr/bin:/custom/pnpm:/custom/bun/bin"
            ],
            homeDirectoryPath: "/Users/liuyuyang"
        )

        XCTAssertEqual(
            paths,
            [
                "/custom/bin",
                "/usr/bin",
                "/custom/pnpm",
                "/custom/bun/bin",
                "/custom/npm/bin",
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/bin",
                "/usr/sbin",
                "/sbin",
                "/Users/liuyuyang/.bun/bin",
                "/Users/liuyuyang/Library/pnpm",
                "/Users/liuyuyang/.npm-global/bin",
                "/Users/liuyuyang/.local/bin",
            ]
        )
    }

    func testInstallationEnvironmentUsesExpandedSearchPaths() {
        let environment = OpenClawInstaller.installationEnvironment(base: [
            "BUN_INSTALL": "/custom/bun"
        ])

        XCTAssertNotNil(environment["PATH"])
        XCTAssertTrue(environment["PATH"]?.contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(environment["PATH"]?.contains("/custom/bun/bin") == true)
        XCTAssertTrue(environment["PATH"]?.contains("\(FileManager.default.homeDirectoryForCurrentUser.path)/.bun/bin") == true)
    }

    func testInstallationSearchPathsPreservesExistingPathPriorityOverGuessedHomeBins() {
        let paths = OpenClawInstaller.installationSearchPaths(
            base: [
                "PATH": "/Users/liuyuyang/.nvm/versions/node/v22.0.0/bin:/opt/homebrew/bin:/usr/bin"
            ],
            homeDirectoryPath: "/Users/liuyuyang"
        )

        XCTAssertEqual(
            Array(paths.prefix(3)),
            [
                "/Users/liuyuyang/.nvm/versions/node/v22.0.0/bin",
                "/opt/homebrew/bin",
                "/usr/bin",
            ]
        )
        XCTAssertEqual(Array(paths.suffix(4)), [
            "/Users/liuyuyang/.bun/bin",
            "/Users/liuyuyang/Library/pnpm",
            "/Users/liuyuyang/.npm-global/bin",
            "/Users/liuyuyang/.local/bin",
        ])
    }

    func testLocalProviderSnapshotReadsConfigFileWhenStatusCommandsFail() throws {
        let configURL = try makeTemporaryOpenClawConfigFile(
            """
            {
              "auth": {
                "profiles": {
                  "litellm:default": {
                    "provider": "litellm",
                    "mode": "api_key"
                  }
                }
              },
              "models": {
                "providers": {
                  "litellm": {
                    "baseUrl": "https://example.com",
                    "models": [{ "id": "gpt-5.4" }]
                  }
                }
              },
              "agents": {
                "defaults": {
                  "model": {
                    "primary": "litellm/gpt-5.4"
                  }
                }
              }
            }
            """
        )

        let snapshot = OpenClawLocalSnapshotSupport.providerSnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            configFileURL: configURL
        )

        XCTAssertEqual(snapshot?.configPath, configURL.path)
        XCTAssertEqual(snapshot?.defaultModelRef, "litellm/gpt-5.4")
        XCTAssertEqual(snapshot?.authStates["litellm"]?.kind, "api_key")
        XCTAssertEqual(snapshot?.authStates["litellm"]?.source, "openclaw.json")
    }

    func testLocalChannelsSnapshotReadsEnabledChannelsFromConfigFile() throws {
        let configURL = try makeTemporaryOpenClawConfigFile(
            """
            {
              "channels": {
                "feishu": {
                  "enabled": true,
                  "appId": "cli_123",
                  "domain": "feishu"
                }
              }
            }
            """
        )

        let snapshot = OpenClawLocalSnapshotSupport.channelsSnapshot(configFileURL: configURL)
        let feishu = snapshot?.channel(id: "feishu")

        XCTAssertEqual(snapshot?.statusFailureDetail, "openclaw channels status/list --json 未返回结果；已回退到 openclaw.json。")
        XCTAssertEqual(feishu?.label, "Feishu")
        XCTAssertEqual(feishu?.configured, true)
        XCTAssertEqual(feishu?.running, false)
        XCTAssertEqual(feishu?.primaryAccount?.accountID, "cli_123")
    }

    func testLocalGatewaySnapshotInfersRunningGatewayProcess() throws {
        let configURL = try makeTemporaryOpenClawConfigFile(
            """
            {
              "gateway": {
                "mode": "local",
                "port": 18789
              }
            }
            """
        )

        let snapshot = OpenClawLocalSnapshotSupport.gatewaySnapshot(
            binaryPath: "/opt/homebrew/bin/openclaw",
            configFileURL: configURL,
            processListProvider: {
                "82363 openclaw-gateway openclaw-gateway\n82361 openclaw /opt/homebrew/bin/openclaw gateway --port 18789\n"
            }
        )

        XCTAssertEqual(snapshot?.state, .running)
        XCTAssertEqual(snapshot?.pid, 82363)
        XCTAssertEqual(snapshot?.runtimeStatus, "running")
    }

    func testOverrideParsesInstalledStateFromEnvironment() {
        let overrideState = OpenClawInstallerOverride.from(environment: [
            "CLAWBAR_TEST_OPENCLAW_STATE": "installed",
            "CLAWBAR_TEST_OPENCLAW_BINARY_PATH": "/opt/homebrew/bin/openclaw",
            "CLAWBAR_TEST_OPENCLAW_DETAIL": "Provider 已配置 · Gateway 可达 · Channel 已就绪",
            "CLAWBAR_TEST_OPENCLAW_EXCERPT": "OpenClaw 2026.4.2"
        ])

        guard case let .installed(snapshot)? = overrideState?.state else {
            return XCTFail("Expected installed override state")
        }

        XCTAssertEqual(snapshot.title, "OpenClaw 已安装")
        XCTAssertEqual(snapshot.detail, "Provider 已配置 · Gateway 可达 · Channel 已就绪")
        XCTAssertEqual(snapshot.excerpt, "OpenClaw 2026.4.2")
        XCTAssertEqual(snapshot.binaryPath, "/opt/homebrew/bin/openclaw")
        XCTAssertEqual(snapshot.healthSnapshot, .deterministicInstalled)
    }

    func testRefreshInstallationStatusUsesOverrideSnapshot() {
        let installer = OpenClawInstaller(
            overrideState: OpenClawInstallerOverride(
                state: .installed(
                    OpenClawStatusSnapshot(
                        title: "OpenClaw 已安装",
                        detail: "Provider 已配置 · Gateway 可达 · Channel 已就绪",
                        excerpt: "OpenClaw 2026.4.2",
                        binaryPath: "/opt/homebrew/bin/openclaw",
                        healthSnapshot: .deterministicInstalled
                    )
                )
            ),
            autoStartTimer: false
        )

        installer.refreshInstallationStatus()

        XCTAssertTrue(installer.isInstalled)
        XCTAssertEqual(installer.statusText, "OpenClaw 已安装")
        XCTAssertEqual(installer.detailText, "Provider 已配置 · Gateway 可达 · Channel 已就绪")
        XCTAssertEqual(installer.statusExcerpt, "OpenClaw 2026.4.2")
        XCTAssertEqual(installer.installedBinaryPath, "/opt/homebrew/bin/openclaw")
        XCTAssertEqual(installer.healthSnapshot, .deterministicInstalled)
        XCTAssertNotNil(installer.lastStatusRefreshDate)
    }

    func testRefreshInstallationStatusLoadsUpdateAvailabilityAlongsideInstalledSnapshot() async {
        let installer = OpenClawInstaller(
            autoStartTimer: false,
            detectBinaryPath: { _ in "/opt/homebrew/bin/openclaw" },
            fetchStatusSnapshot: { _, _ in
                OpenClawStatusSnapshot(
                    title: "OpenClaw 已安装",
                    detail: "Provider 已配置 · Gateway 可达 · Channel 已就绪",
                    excerpt: "OpenClaw 2026.4.2",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    healthSnapshot: .deterministicInstalled
                )
            },
            fetchUpdateStatusSnapshot: { _, _ in
                OpenClawUpdateStatusSnapshot(
                    isUpdateAvailable: true,
                    latestVersion: "2026.4.3",
                    channelLabel: "stable (default)"
                )
            }
        )

        installer.refreshInstallationStatus(force: true)
        await waitForCondition { installer.latestVersion == "2026.4.3" }

        XCTAssertTrue(installer.isInstalled)
        XCTAssertEqual(installer.isUpdateAvailable, true)
        XCTAssertEqual(installer.latestVersion, "2026.4.3")
        XCTAssertEqual(installer.channelLabel, "stable (default)")
    }

    func testPrepareGatewayServiceReturnsReadyWhenInstallRegistersLaunchAgent() {
        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { "generated-token" },
            runGatewayCommand: { command, _, _ in
                XCTAssertEqual(command, OpenClawInstaller.gatewayInstallCommand)
                return OpenClawGatewayCommandResult(
                    output: #"{"ok":true,"message":"Gateway service installed."}"#,
                    exitStatus: 0,
                    timedOut: false
                )
            },
            fetchGatewayStatus: { _, _ in
                OpenClawGatewayStatusSnapshot(
                    state: .stopped,
                    detail: "service not loaded",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    runtimeStatus: nil,
                    serviceInstalled: true,
                    serviceLoaded: false,
                    serviceLabel: "LaunchAgent",
                    pid: nil,
                    missingUnit: false
                )
            }
        )

        XCTAssertTrue(result.isReady)
        XCTAssertEqual(result.token, "generated-token")
        XCTAssertNil(result.failureDetail)
    }

    func testPrepareGatewayServiceFailsWhenGatewayInstallLeavesMissingUnit() {
        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { "generated-token" },
            runGatewayCommand: { _, _, _ in
                OpenClawGatewayCommandResult(
                    output: #"{"ok":true,"message":"Gateway service installed."}"#,
                    exitStatus: 0,
                    timedOut: false
                )
            },
            fetchGatewayStatus: { _, _ in
                OpenClawGatewayStatusSnapshot(
                    state: .missing,
                    detail: "Bad request. Could not find service ai.openclaw.gateway",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    runtimeStatus: "unknown",
                    serviceInstalled: false,
                    serviceLoaded: false,
                    serviceLabel: "LaunchAgent",
                    pid: nil,
                    missingUnit: true
                )
            }
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.failureDetail, "Gateway 服务安装命令已完成，但 launchd 中仍未注册 ai.openclaw.gateway。")
    }

    func testPrepareGatewayServiceFailsWhenTokenConfigurationFails() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "token write failed" }
        }

        let result = OpenClawInstaller.prepareGatewayService(
            binaryPath: "/opt/homebrew/bin/openclaw",
            environment: [:],
            configureGateway: { throw TestError() }
        )

        XCTAssertFalse(result.isReady)
        XCTAssertEqual(result.failureDetail, "Gateway token 初始化失败：token write failed")
    }

    func testRefreshInstallationStatusUsesMissingOverride() {
        let installer = OpenClawInstaller(
            overrideState: OpenClawInstallerOverride(state: .missing),
            autoStartTimer: false
        )

        installer.refreshInstallationStatus()

        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.installedBinaryPath)
        XCTAssertEqual(installer.statusText, "准备安装 OpenClaw。")
        XCTAssertEqual(installer.detailText, "点击按钮后会执行官方安装脚本，但不会进入 onboarding。")
    }

    func testRefreshInstallationStatusKeepsInstalledStateWhenUpdateStatusIsUnavailable() async {
        let installer = OpenClawInstaller(
            autoStartTimer: false,
            detectBinaryPath: { _ in "/opt/homebrew/bin/openclaw" },
            fetchStatusSnapshot: { _, _ in
                OpenClawStatusSnapshot(
                    title: "OpenClaw 已安装",
                    detail: "Provider 已配置 · Gateway 可达 · Channel 已就绪",
                    excerpt: "OpenClaw 2026.4.2",
                    binaryPath: "/opt/homebrew/bin/openclaw",
                    healthSnapshot: .deterministicInstalled
                )
            },
            fetchUpdateStatusSnapshot: { _, _ in nil }
        )

        installer.refreshInstallationStatus(force: true)
        await waitForCondition { installer.lastStatusRefreshDate != nil }

        XCTAssertTrue(installer.isInstalled)
        XCTAssertNil(installer.isUpdateAvailable)
        XCTAssertNil(installer.latestVersion)
        XCTAssertNil(installer.channelLabel)
        XCTAssertEqual(installer.statusText, "OpenClaw 已安装")
    }

    func testStartUpdateIfNeededMarksInstallerBusyDuringUpgrade() async {
        let installer = OpenClawInstaller(
            autoStartTimer: false,
            processFactory: { _, _, environment, _, completion in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = ["-lc", "sleep 0.1"]
                process.environment = environment
                process.standardOutput = Pipe()
                process.standardError = Pipe()
                process.terminationHandler = { _ in
                    completion(.success(()))
                }
                return process
            }
        )

        installer.startUpdateIfNeeded()

        XCTAssertTrue(installer.isUpdating)
        XCTAssertTrue(installer.isBusy)

        await waitForCondition { !installer.isUpdating }
        XCTAssertFalse(installer.isBusy)
    }

    func testSharedInstallerStartsWithUserFacingIdleMessages() {
        let installer = OpenClawInstaller(autoStartTimer: false)

        XCTAssertFalse(installer.isInstalling)
        XCTAssertFalse(installer.isUpdating)
        XCTAssertFalse(installer.isUninstalling)
        XCTAssertFalse(installer.isInstalled)
        XCTAssertNil(installer.lastStatusRefreshDate)
        XCTAssertEqual(installer.statusText, "准备安装 OpenClaw。")
        XCTAssertEqual(installer.detailText, "点击按钮后会执行官方安装脚本，但不会进入 onboarding。")
    }

    private func waitForCondition(
        timeout: TimeInterval = 1,
        pollInterval: UInt64 = 10_000_000,
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(nanoseconds: pollInterval)
        }
    }

    private func makeTemporaryOpenClawConfigFile(_ contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let fileURL = directoryURL.appendingPathComponent("openclaw.json")
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
