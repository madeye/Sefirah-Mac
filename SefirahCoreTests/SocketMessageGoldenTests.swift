import SefirahCore
import XCTest

/// Fixtures follow System.Text.Json output:
/// camelCase properties, PascalCase `type` discriminator, PascalCase string
/// enums, integer `AudioStreamType`, nulls included the way C# writes them.
final class SocketMessageGoldenTests: XCTestCase {
    func testEveryDiscriminatorIsRegistered() {
        XCTAssertEqual(SocketMessage.allTypeNames.count, 35)
        XCTAssertEqual(Set(SocketMessage.allTypeNames).count, 35)
    }

    func testUnknownTypeThrows() {
        XCTAssertThrowsError(try NDJSONCodec.decodeMessage(from: #"{"type":"NotARealMessage"}"#)) { error in
            XCTAssertEqual(error as? SocketCodecError, .unknownType("NotARealMessage"))
        }
    }

    func testMissingTypeThrows() {
        XCTAssertThrowsError(try NDJSONCodec.decodeMessage(from: #"{"pair":true}"#)) { error in
            XCTAssertEqual(error as? SocketCodecError, .missingType)
        }
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try NDJSONCodec.decodeMessage(from: "   \n")) { error in
            XCTAssertEqual(error as? SocketCodecError, .emptyInput)
        }
    }

    func testDisconnect() throws {
        try assertGolden(#"{"type":"Disconnect"}"#, equals: .disconnect)
    }

    func testClearNotifications() throws {
        try assertGolden(#"{"type":"ClearNotifications"}"#, equals: .clearNotifications)
    }

    func testRequestApplicationList() throws {
        try assertGolden(#"{"type":"RequestApplicationList"}"#, equals: .requestApplicationList)
    }

    func testBluetoothPairingRequest() throws {
        try assertGolden(#"{"type":"BluetoothPairingRequest"}"#, equals: .bluetoothPairingRequest)
    }

    func testRequestWorkerLaunch() throws {
        try assertGolden(
            #"{"type":"RequestWorkerLaunch","command":"am start -n com.foo/.Bar"}"#,
            equals: .requestWorkerLaunch(RequestWorkerLaunch(command: "am start -n com.foo/.Bar"))
        )
    }

    func testAuthentication() throws {
        try assertGolden(
            #"{"type":"Authentication","deviceId":"dev-1","deviceName":"Pixel 8","publicKey":"MFkwEwYH","model":"shiba"}"#,
            equals: .authentication(
                Authentication(deviceId: "dev-1", deviceName: "Pixel 8", publicKey: "MFkwEwYH", model: "shiba")
            )
        )
    }

    func testPairMessageTrueAndFalse() throws {
        try assertGolden(#"{"type":"PairMessage","pair":true}"#, equals: .pairMessage(PairMessage(pair: true)))
        try assertGolden(#"{"type":"PairMessage","pair":false}"#, equals: .pairMessage(PairMessage(pair: false)))
    }

    func testBluetoothPairingResultWithNullName() throws {
        try assertGolden(
            #"{"type":"BluetoothPairingResult","granted":true,"deviceName":null}"#,
            equals: .bluetoothPairingResult(BluetoothPairingResult(granted: true, deviceName: nil))
        )
    }

    func testUdpBroadcast() throws {
        try assertGolden(
            #"{"type":"UdpBroadcast","port":5150,"deviceId":"abc","deviceName":"Studio"}"#,
            equals: .udpBroadcast(UdpBroadcast(port: 5150, deviceId: "abc", deviceName: "Studio"))
        )
    }

    func testDeviceInfoWithNullAvatar() throws {
        try assertGolden(
            #"{"type":"DeviceInfo","deviceName":"Mac","avatar":null,"phoneNumbers":[{"number":"+15551212","subscriptionId":0}]}"#,
            equals: .deviceInfo(
                DeviceInfo(
                    deviceName: "Mac",
                    avatar: nil,
                    phoneNumbers: [PhoneNumber(number: "+15551212", subscriptionId: 0)]
                )
            )
        )
    }

    func testBatteryState() throws {
        try assertGolden(
            #"{"type":"BatteryState","batteryLevel":42,"isCharging":true}"#,
            equals: .batteryState(BatteryState(batteryLevel: 42, isCharging: true))
        )
    }

    func testRingerModeAndDnd() throws {
        try assertGolden(#"{"type":"RingerModeState","mode":1}"#, equals: .ringerModeState(RingerModeState(mode: 1)))
        try assertGolden(#"{"type":"DndState","isEnabled":true}"#, equals: .dndState(DndState(isEnabled: true)))
    }

    func testCallInfoUsesPascalCaseEnum() throws {
        try assertGolden(
            #"{"type":"CallInfo","callState":"Ringing","phoneNumber":"+1555","contactInfo":null}"#,
            equals: .callInfo(CallInfo(callState: .ringing, phoneNumber: "+1555", contactInfo: nil))
        )
    }

    func testCallLogInfo() throws {
        try assertGolden(
            #"{"type":"CallLogInfo","callLogId":9,"phoneNumber":"+1","timestampMillis":1700000000000,"durationSeconds":12,"callType":"Missed","contactInfo":null}"#,
            equals: .callLogInfo(
                CallLogInfo(
                    callLogId: 9,
                    phoneNumber: "+1",
                    timestampMillis: 1_700_000_000_000,
                    durationSeconds: 12,
                    callType: .missed,
                    contactInfo: nil
                )
            )
        )
    }

    func testAudioStreamStateIsIntegerEnum() throws {
        try assertGolden(
            #"{"type":"AudioStreamState","streamType":3,"level":7}"#,
            equals: .audioStreamState(AudioStreamState(streamType: .media, level: 7))
        )
        let encoded = try NDJSONCodec.encodeMessage(
            .audioStreamState(AudioStreamState(streamType: .ring, level: 1))
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["streamType"] as? Int, 2)
        XCTAssertNotEqual(object["streamType"] as? String, "Ring")
    }

    func testAudioDeviceInfo() throws {
        try assertGolden(
            #"{"type":"AudioDeviceInfo","infoType":"New","deviceId":"out-1","deviceName":"Mac Speakers","volume":0.5,"isMuted":false,"isSelected":true}"#,
            equals: .audioDeviceInfo(
                AudioDeviceInfo(
                    infoType: .new,
                    deviceId: "out-1",
                    deviceName: "Mac Speakers",
                    volume: 0.5,
                    isMuted: false,
                    isSelected: true
                )
            )
        )
    }

    func testConversationAndTextMessageNestedWithoutType() throws {
        let json = """
        {"type":"ConversationInfo","infoType":"New","threadId":44,"recipients":["+1555"],"messages":[{"uniqueId":1,"addresses":["+1555"],"threadId":44,"body":"hi","timestamp":1,"messageType":1,"read":false,"subscriptionId":0,"attachments":null,"isTextMessage":true,"hasMultipleRecipients":false}]}
        """
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .conversationInfo(let info) = decoded else {
            return XCTFail("expected ConversationInfo")
        }
        XCTAssertEqual(info.infoType, .new)
        XCTAssertEqual(info.messages.count, 1)
        XCTAssertEqual(info.messages[0].body, "hi")
        XCTAssertNil(info.messages[0].attachments)

        let encoded = try NDJSONCodec.encodeMessage(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        XCTAssertNil(messages[0]["type"], "nested TextMessage must not carry the SocketMessage discriminator")
    }

    func testThreadRequestDefaults() throws {
        try assertGolden(
            #"{"type":"ThreadRequest","threadId":7,"rangeStartTimestamp":-1,"numberToRequest":-1}"#,
            equals: .threadRequest(ThreadRequest(threadId: 7))
        )
    }

    func testContactInfo() throws {
        try assertGolden(
            #"{"type":"ContactInfo","id":"c1","lookupKey":"key","displayName":"Ada","number":"+1","photoBase64":""}"#,
            equals: .contactInfo(
                ContactInfo(id: "c1", lookupKey: "key", displayName: "Ada", number: "+1", photoBase64: "")
            )
        )
    }

    func testNotificationInfoWithActionsAndReply() throws {
        let json = """
        {"type":"NotificationInfo","notificationKey":"n1","infoType":"New","timestampMillis":2,"appPackage":"com.chat","appName":"Chat","title":"Ada","text":"hello","messages":[{"sender":"Ada","text":"hello"}],"groupKey":null,"tag":null,"actions":[{"notificationKey":"n1","label":"Reply","actionIndex":0}],"replyResultKey":"reply","appIcon":null,"largeIcon":""}
        """
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        guard case .notificationInfo(let info) = decoded else {
            return XCTFail("expected NotificationInfo")
        }
        XCTAssertEqual(info.infoType, .new)
        XCTAssertEqual(info.actions.first?.label, "Reply")
        XCTAssertEqual(info.messages.first?.sender, "Ada")

        let encoded = try NDJSONCodec.encodeMessage(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        XCTAssertNil(actions[0]["type"], "nested NotificationAction must not carry the discriminator")
    }

    func testNotificationActionAndReplyAsRoot() throws {
        try assertGolden(
            #"{"type":"NotificationAction","notificationKey":"n1","label":"Mark","actionIndex":1}"#,
            equals: .notificationAction(
                NotificationAction(notificationKey: "n1", label: "Mark", actionIndex: 1)
            )
        )
        try assertGolden(
            #"{"type":"NotificationReply","notificationKey":"n1","replyResultKey":"rk","replyText":"ok"}"#,
            equals: .notificationReply(
                NotificationReply(notificationKey: "n1", replyResultKey: "rk", replyText: "ok")
            )
        )
    }

    func testFileTransferInfo() throws {
        try assertGolden(
            #"{"type":"FileTransferInfo","files":[{"fileName":"a.png","mimeType":"image/png","fileSize":123}],"serverInfo":{"port":5152},"isClipboard":true}"#,
            equals: .fileTransferInfo(
                FileTransferInfo(
                    files: [FileMetadata(fileName: "a.png", mimeType: "image/png", fileSize: 123)],
                    serverInfo: ServerInfo(port: 5152),
                    isClipboard: true
                )
            )
        )
    }

    func testSftpServerInfo() throws {
        try assertGolden(
            #"{"type":"SftpServerInfo","username":"u","password":"p","port":2222,"paths":["/sdcard"],"pathNames":["Internal"]}"#,
            equals: .sftpServerInfo(
                SftpServerInfo(username: "u", password: "p", port: 2222, paths: ["/sdcard"], pathNames: ["Internal"])
            )
        )
    }

    func testClipboardInfo() throws {
        try assertGolden(
            #"{"type":"ClipboardInfo","clipboardType":"text/plain","content":"hello"}"#,
            equals: .clipboardInfo(ClipboardInfo(clipboardType: "text/plain", content: "hello"))
        )
    }

    func testPlaybackInfoPascalCaseEnum() throws {
        try assertGolden(
            #"{"type":"PlaybackInfo","infoType":"PlaybackInfo","source":"spotify","trackTitle":"Song","artist":"Artist","isPlaying":true,"isShuffleActive":null,"repeatMode":null,"playbackRate":null,"position":12.5,"maxSeekTime":200,"minSeekTime":0,"thumbnail":null,"appName":"Spotify","volume":80,"canPlay":true,"canPause":true,"canGoNext":true,"canGoPrevious":false,"canSeek":true}"#,
            equals: .playbackInfo(
                PlaybackInfo(
                    infoType: .playbackInfo,
                    source: "spotify",
                    trackTitle: "Song",
                    artist: "Artist",
                    isPlaying: true,
                    position: 12.5,
                    maxSeekTime: 200,
                    minSeekTime: 0,
                    appName: "Spotify",
                    volume: 80,
                    canPlay: true,
                    canPause: true,
                    canGoNext: true,
                    canGoPrevious: false,
                    canSeek: true
                )
            )
        )
    }

    func testMediaAndAudioActions() throws {
        try assertGolden(
            #"{"type":"MediaAction","actionType":"Play","source":"spotify","value":null}"#,
            equals: .mediaAction(MediaAction(actionType: .play, source: "spotify", value: nil))
        )
        try assertGolden(
            #"{"type":"AudioAction","actionType":"VolumeUpdate","source":"out-1","value":0.4}"#,
            equals: .audioAction(AudioAction(actionType: .volumeUpdate, source: "out-1", value: 0.4))
        )
    }

    func testPlaySound() throws {
        try assertGolden(
            #"{"type":"PlaySound","isPlaying":true}"#,
            equals: .playSound(PlaySound(isPlaying: true))
        )
    }

    func testApplicationListNestedWithoutType() throws {
        let json = #"{"type":"ApplicationList","appList":[{"packageName":"com.foo","appName":"Foo","appIcon":null}]}"#
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        let encoded = try NDJSONCodec.encodeMessage(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let apps = try XCTUnwrap(object["appList"] as? [[String: Any]])
        XCTAssertNil(apps[0]["type"])
        XCTAssertEqual(apps[0]["packageName"] as? String, "com.foo")
    }

    func testApplicationInfoAsRoot() throws {
        try assertGolden(
            #"{"type":"ApplicationInfo","packageName":"com.foo","appName":"Foo","appIcon":null}"#,
            equals: .applicationInfo(ApplicationInfo(packageName: "com.foo", appName: "Foo", appIcon: nil))
        )
    }

    func testActionListAndActionInfo() throws {
        try assertGolden(
            #"{"type":"ActionInfo","actionId":"lock","actionName":"Lock","icon":null,"askForConfirmation":true}"#,
            equals: .actionInfo(
                ActionInfo(actionId: "lock", actionName: "Lock", icon: nil, askForConfirmation: true)
            )
        )
        let listJSON = #"{"type":"ActionList","actions":[{"actionId":"lock","actionName":"Lock","icon":null,"askForConfirmation":false}]}"#
        let decoded = try NDJSONCodec.decodeMessage(from: listJSON)
        guard case .actionList(let list) = decoded else {
            return XCTFail("expected ActionList")
        }
        XCTAssertEqual(list.actions.first?.actionId, "lock")
        let encoded = try NDJSONCodec.encodeMessage(decoded)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let actions = try XCTUnwrap(object["actions"] as? [[String: Any]])
        XCTAssertNil(actions[0]["type"])
    }

    func testEncodeWritesPascalCaseDiscriminatorNotCamelCase() throws {
        let data = try NDJSONCodec.encodeMessage(
            .authentication(Authentication(deviceId: "a", deviceName: "b", publicKey: "c", model: "d"))
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "Authentication")
        XCTAssertNil(object["Type"])
        XCTAssertEqual(object["deviceId"] as? String, "a")
        XCTAssertNil(object["DeviceId"])
    }

    func testRoundTripEveryGolden() throws {
        let samples: [SocketMessage] = [
            .disconnect,
            .clearNotifications,
            .requestApplicationList,
            .bluetoothPairingRequest,
            .requestWorkerLaunch(RequestWorkerLaunch(command: "cmd")),
            .authentication(Authentication(deviceId: "id", deviceName: "n", publicKey: "k", model: "m")),
            .pairMessage(PairMessage(pair: true)),
            .bluetoothPairingResult(BluetoothPairingResult(granted: false, deviceName: "buds")),
            .udpBroadcast(UdpBroadcast(port: 5151, deviceId: "id", deviceName: "n")),
            .deviceInfo(DeviceInfo(deviceName: "Mac", phoneNumbers: [])),
            .batteryState(BatteryState(batteryLevel: 1, isCharging: false)),
            .ringerModeState(RingerModeState(mode: 0)),
            .dndState(DndState(isEnabled: false)),
            .callInfo(CallInfo(callState: .inProgress, phoneNumber: "1")),
            .callLogInfo(
                CallLogInfo(
                    callLogId: 1,
                    timestampMillis: 2,
                    durationSeconds: 3,
                    callType: .outgoing
                )
            ),
            .audioStreamState(AudioStreamState(streamType: .notification, level: 3)),
            .audioDeviceInfo(
                AudioDeviceInfo(infoType: .active, deviceId: "d", volume: 1, isMuted: true, isSelected: false)
            ),
            .conversationInfo(ConversationInfo(infoType: .active, threadId: 1)),
            .textMessage(TextMessage(threadId: 1, body: "x", timestamp: 2, messageType: 1)),
            .threadRequest(ThreadRequest(threadId: 3, rangeStartTimestamp: 4, numberToRequest: 5)),
            .contactInfo(ContactInfo(lookupKey: "l", displayName: "n", number: "1")),
            .notificationInfo(NotificationInfo(notificationKey: "k", infoType: .removed, timestampMillis: 1)),
            .notificationAction(NotificationAction(actionIndex: 0)),
            .notificationReply(NotificationReply(notificationKey: "k", replyResultKey: "r", replyText: "t")),
            .fileTransferInfo(
                FileTransferInfo(files: [FileMetadata(fileName: "f", mimeType: "text/plain", fileSize: 1)], serverInfo: ServerInfo(port: 5153))
            ),
            .sftpServerInfo(SftpServerInfo(username: "u", password: "p", port: 22)),
            .clipboardInfo(ClipboardInfo(clipboardType: "text/plain", content: "c")),
            .playbackInfo(PlaybackInfo(infoType: .removedSession, source: "s", isPlaying: false)),
            .mediaAction(MediaAction(actionType: .next, source: "s")),
            .audioAction(AudioAction(actionType: .toggleMute, source: "s")),
            .playSound(PlaySound(isPlaying: false)),
            .applicationList(ApplicationList(appList: [])),
            .applicationInfo(ApplicationInfo(packageName: "p", appName: "n")),
            .actionInfo(ActionInfo(actionId: "a", actionName: "n")),
            .actionList(ActionList(actions: [])),
        ]
        XCTAssertEqual(samples.count, SocketMessage.allTypeNames.count)
        for sample in samples {
            let data = try NDJSONCodec.encodeMessage(sample)
            let decoded = try NDJSONCodec.decodeMessage(from: data)
            XCTAssertEqual(decoded, sample, "round-trip failed for \(sample.typeName)")
            XCTAssertEqual(decoded.typeName, sample.typeName)
        }
    }

    private func assertGolden(_ json: String, equals expected: SocketMessage) throws {
        let decoded = try NDJSONCodec.decodeMessage(from: json)
        XCTAssertEqual(decoded, expected)
        let encoded = try NDJSONCodec.encodeMessage(decoded)
        let roundTrip = try NDJSONCodec.decodeMessage(from: encoded)
        XCTAssertEqual(roundTrip, expected)
        XCTAssertEqual(decoded.typeName, expected.typeName)
    }
}
