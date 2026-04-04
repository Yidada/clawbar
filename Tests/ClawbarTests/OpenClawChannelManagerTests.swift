import XCTest
@testable import Clawbar

final class OpenClawChannelManagerTests: XCTestCase {
    func testParsePluginInstalledReturnsTrueWhenWeixinPluginExistsInJSON() {
        let output = """
        {
          "plugins": [
            {
              "id": "openclaw-weixin",
              "name": "WeixinClawBot"
            }
          ]
        }
        """

        XCTAssertTrue(OpenClawChannelManager.parsePluginInstalled(output))
    }

    func testParseBindingDetectedReturnsTrueWhenCredentialsContainWeixinEntry() {
        XCTAssertTrue(
            OpenClawChannelManager.parseBindingDetected(
                statusOutput: "{}",
                credentialEntries: ["openclaw-weixin", "oauth.json"]
            )
        )
    }

    func testParseBindingDetectedReturnsTrueForConnectedWeixinStatusOutput() {
        let output = """
        {
          "channels": [
            {
              "id": "openclaw-weixin",
              "status": "connected"
            }
          ]
        }
        """

        XCTAssertTrue(
            OpenClawChannelManager.parseBindingDetected(
                statusOutput: output,
                credentialEntries: []
            )
        )
    }

    func testMakeTerminalLaunchArgumentsWrapsShellCommandForTerminal() {
        let command = OpenClawChannelManager.makeTerminalShellCommand(
            command: "openclaw channels login --channel openclaw-weixin",
            path: "/opt/homebrew/bin:/usr/bin:/bin"
        )
        let arguments = OpenClawChannelManager.makeTerminalLaunchArguments(shellCommand: command)

        XCTAssertEqual(arguments[0], "-e")
        XCTAssertEqual(arguments[1], #"tell application "Terminal""#)
        let joined = arguments.joined(separator: " ")
        XCTAssertTrue(joined.contains("do script"))
        XCTAssertTrue(joined.contains("export PATH="))
        XCTAssertTrue(joined.contains("openclaw channels login --channel openclaw-weixin"))
    }
}
