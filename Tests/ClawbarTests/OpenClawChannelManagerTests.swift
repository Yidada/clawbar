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

    func testParseRuntimeSnapshotExtractsQRCodeAndProgressSignals() {
        let output = """
        Installed plugin: openclaw-weixin
        Restart the gateway to load plugins.
        [openclaw-weixin] 插件就绪，开始首次连接...
        使用微信扫描以下二维码，以完成连接：
        https://liteapp.weixin.qq.com/q/7GiQu1?qrcode=edc16d9d61346c3ec3ada33da3f312a6&bot_type=3
        等待连接结果...
        """

        let snapshot = OpenClawChannelManager.parseRuntimeSnapshot(from: output)

        XCTAssertTrue(snapshot.pluginInstalled)
        XCTAssertTrue(snapshot.pluginReadyForLogin)
        XCTAssertTrue(snapshot.waitingForConnection)
        XCTAssertEqual(
            snapshot.qrCodeURL,
            "https://liteapp.weixin.qq.com/q/7GiQu1?qrcode=edc16d9d61346c3ec3ada33da3f312a6&bot_type=3"
        )
    }

    func testParseRuntimeSnapshotMarksConnectedAndGatewayRestart() {
        let output = """
        ✅ 与微信连接成功！
        [openclaw-weixin] 正在重启 OpenClaw Gateway...
        """

        let snapshot = OpenClawChannelManager.parseRuntimeSnapshot(from: output)

        XCTAssertTrue(snapshot.connected)
        XCTAssertTrue(snapshot.restartingGateway)
    }
}
