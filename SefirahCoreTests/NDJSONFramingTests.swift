import SefirahCore
import XCTest

final class NDJSONFramingTests: XCTestCase {
    func testEncodeLineAppendsNewline() throws {
        let data = try NDJSONCodec.encodeLine(.disconnect)
        XCTAssertEqual(data.last, 0x0A)
        var buffer = data
        let lines = NDJSONCodec.popCompleteLines(from: &buffer)
        XCTAssertEqual(lines, [#"{"type":"Disconnect"}"#])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testPopCompleteLinesLeavesPartialFragment() throws {
        var buffer = Data("{\"type\":\"Disconnect\"}\n{\"type\":\"PairMes".utf8)
        let lines = NDJSONCodec.popCompleteLines(from: &buffer)
        XCTAssertEqual(lines, [#"{"type":"Disconnect"}"#])
        XCTAssertEqual(String(data: buffer, encoding: .utf8), #"{"type":"PairMes"#)
    }

    func testPopCompleteLinesSkipsBlankLines() throws {
        var buffer = Data("\n\n{\"type\":\"Disconnect\"}\n\n".utf8)
        let lines = NDJSONCodec.popCompleteLines(from: &buffer)
        XCTAssertEqual(lines, [#"{"type":"Disconnect"}"#])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeLinesTrimsWhitespaceLikeCSharp() throws {
        var buffer = Data("  {\"type\":\"Disconnect\"}  \r\n".utf8)
        let messages = try NDJSONCodec.decodeLines(from: &buffer)
        XCTAssertEqual(messages, [.disconnect])
    }

    func testMultipleMessagesInOneBuffer() throws {
        let first = try NDJSONCodec.encodeLine(.pairMessage(PairMessage(pair: true)))
        let second = try NDJSONCodec.encodeLine(.disconnect)
        var buffer = first + second
        let messages = try NDJSONCodec.decodeLines(from: &buffer)
        XCTAssertEqual(messages, [.pairMessage(PairMessage(pair: true)), .disconnect])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDecodeLinesSkipsUnknownTypeAndKeepsValidMessages() throws {
        var buffer = Data()
        buffer.append(contentsOf: #"{"type":"NotARealMessage"}"#.utf8)
        buffer.append(0x0A)
        buffer.append(contentsOf: try NDJSONCodec.encodeLine(.disconnect))
        let lines = NDJSONCodec.popCompleteLines(from: &buffer)
        var decoded: [SocketMessage] = []
        for line in lines {
            if let message = try? NDJSONCodec.decodeMessage(from: line) {
                decoded.append(message)
            }
        }
        XCTAssertEqual(decoded, [.disconnect])
        XCTAssertTrue(buffer.isEmpty)
    }

    func testDeviceInfoDecodesMissingPhoneNumbers() throws {
        let json = #"{"type":"DeviceInfo","deviceName":"Pixel","avatar":null}"#
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .deviceInfo(let info) = decoded else {
            return XCTFail("DeviceInfo")
        }
        XCTAssertEqual(info.deviceName, "Pixel")
        XCTAssertTrue(info.phoneNumbers.isEmpty)
    }

    func testConversationInfoDecodesAndroidOmittedDefaults() throws {
        // kotlinx Json encodeDefaults=false: Active snapshots often omit recipients,
        // and nested TextMessage omits read/subscriptionId/isTextMessage/hasMultipleRecipients.
        let json = #"{"type":"ConversationInfo","infoType":"Active","threadId":44,"messages":[{"uniqueId":9,"addresses":["+1555"],"threadId":44,"body":"hi","timestamp":10,"messageType":1}]}"#
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .conversationInfo(let info) = decoded else {
            return XCTFail("ConversationInfo")
        }
        XCTAssertEqual(info.infoType, .active)
        XCTAssertEqual(info.threadId, 44)
        XCTAssertTrue(info.recipients.isEmpty)
        XCTAssertEqual(info.messages.count, 1)
        XCTAssertEqual(info.messages[0].body, "hi")
        XCTAssertFalse(info.messages[0].read)
        XCTAssertEqual(info.messages[0].subscriptionId, 0)
        XCTAssertFalse(info.messages[0].isTextMessage)
    }

    func testConversationInfoRemovedOmitsLists() throws {
        let json = #"{"type":"ConversationInfo","infoType":"Removed","threadId":7}"#
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .conversationInfo(let info) = decoded else {
            return XCTFail("ConversationInfo")
        }
        XCTAssertEqual(info.infoType, .removed)
        XCTAssertTrue(info.recipients.isEmpty)
        XCTAssertTrue(info.messages.isEmpty)
    }

    func testNotificationInfoOmitsOptionalArrays() throws {
        let json = #"{"type":"NotificationInfo","notificationKey":"n1","infoType":"New","title":"Hi"}"#
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .notificationInfo(let info) = decoded else {
            return XCTFail("NotificationInfo")
        }
        XCTAssertEqual(info.title, "Hi")
        XCTAssertTrue(info.messages.isEmpty)
        XCTAssertTrue(info.actions.isEmpty)
        XCTAssertEqual(info.largeIcon, "")
    }
}
