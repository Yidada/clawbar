import XCTest
@testable import Clawbar

final class ProviderManagementDisplayStateTests: XCTestCase {
    func testBindingStateTitlesMatchOllamaOnlyFlow() {
        XCTAssertEqual(OpenClawBindingState.ready.title, "OpenClaw 已绑定 Gemma 4")
        XCTAssertEqual(OpenClawBindingState.ready.statusLabel, "已绑定")
        XCTAssertEqual(OpenClawBindingState.waitingForOllama.title, "等待内置 Ollama")
        XCTAssertEqual(OpenClawBindingState.waitingForOllama.statusLabel, "等待中")
    }

    func testEmbeddedOllamaMatchesSupportedModelWithAndWithoutTag() {
        XCTAssertTrue(EmbeddedOllamaManager.matchesSupportedModel("gemma4"))
        XCTAssertTrue(EmbeddedOllamaManager.matchesSupportedModel("gemma4:latest"))
        XCTAssertFalse(EmbeddedOllamaManager.matchesSupportedModel("llama3.3"))
    }

    func testParseModelNamesReadsTagsPayload() {
        let data = Data(
            """
            {
              "models": [
                { "name": "gemma4:latest" },
                { "name": "qwen3:14b" }
              ]
            }
            """.utf8
        )

        XCTAssertEqual(
            EmbeddedOllamaManager.parseModelNames(from: data),
            ["gemma4:latest", "qwen3:14b"]
        )
    }

    func testResolveAvailableCLIPathFallsBackToManagedRuntimeDirectory() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let runtimeURL = rootURL.appendingPathComponent("runtime", isDirectory: true)
        let cliURL = runtimeURL.appendingPathComponent("ollama", isDirectory: false)
        try FileManager.default.createDirectory(at: runtimeURL, withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: cliURL.path, contents: Data("#!/bin/sh\n".utf8)))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let resolvedPath = EmbeddedOllamaManager.resolveAvailableCLIPath(
            environment: [EmbeddedOllamaManager.testManagedRuntimeDirectoryEnvironmentKey: runtimeURL.path],
            resourceURL: nil
        )

        XCTAssertEqual(resolvedPath, cliURL.path)
    }

    @MainActor
    func testRuntimeSummaryExplainsInstallEntryWhenMissing() {
        let manager = EmbeddedOllamaManager(
            environmentProvider: { [:] },
            resourceURLProvider: { nil },
            runCommand: { _, _, _, _ in
                EmbeddedOllamaCommandResult(output: "", exitStatus: 0, timedOut: false)
            },
            probeModels: { _, _ in [] },
            installRuntime: { _, _ in "/tmp/ollama" }
        )

        XCTAssertTrue(manager.runtimeSummary.contains("下载安装"))
    }
}
