import SefirahCore
import XCTest

final class FeatureHubTests: XCTestCase {
    func testNotificationPersistReplyAndAction() throws {
        let hub = try makeHub()
        let inbound = SocketMessage.notificationInfo(
            NotificationInfo(
                notificationKey: "n1",
                infoType: .new,
                timestampMillis: 99,
                appPackage: "com.chat",
                appName: "Chat",
                title: "Ada",
                text: "hello",
                actions: [NotificationAction(notificationKey: "n1", label: "Mark", actionIndex: 0)],
                replyResultKey: "rk"
            )
        )
        _ = try hub.handle(deviceId: "phone", inbound)
        let notes = try hub.notifications(deviceId: "phone")
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes[0].title, "Ada")
        XCTAssertEqual(notes[0].actions.first?.label, "Mark")

        let reply = hub.reply(deviceId: "phone", notificationKey: "n1", replyResultKey: "rk", text: "ok")
        guard case .notificationReply(let payload) = reply else { return XCTFail("reply") }
        XCTAssertEqual(payload.replyText, "ok")
        XCTAssertEqual(payload.notificationKey, "n1")

        let action = hub.invokeAction(deviceId: "phone", notificationKey: "n1", index: 0, label: "Mark")
        guard case .notificationAction(let invoked) = action else { return XCTFail("action") }
        XCTAssertEqual(invoked.actionIndex, 0)

        _ = try hub.handle(deviceId: "phone", .clearNotifications)
        XCTAssertTrue(try hub.notifications(deviceId: "phone").isEmpty)
    }

    func testClipboardAndFileTransferAndCallInfo() throws {
        let hub = try makeHub()
        let clipboard = ClipboardInfo(clipboardType: "text/plain", content: "copied")
        let clipboardResult = try hub.handle(deviceId: "phone", .clipboardInfo(clipboard))
        XCTAssertEqual(hub.liveState(deviceId: "phone").clipboard?.content, "copied")
        XCTAssertEqual(clipboardResult.effects, [.applyClipboard(clipboard)])

        let transfer = FileTransferInfo(
            files: [FileMetadata(fileName: "a.png", mimeType: "image/png", fileSize: 12)],
            serverInfo: ServerInfo(port: 5152),
            isClipboard: false
        )
        let transferResult = try hub.handle(deviceId: "phone", .fileTransferInfo(transfer))
        XCTAssertEqual(hub.liveState(deviceId: "phone").lastTransfer?.serverInfo.port, 5152)
        XCTAssertEqual(transferResult.effects, [.receiveFiles(transfer)])

        _ = try hub.handle(
            deviceId: "phone",
            .callInfo(CallInfo(callState: .ringing, phoneNumber: "+1555"))
        )
        XCTAssertEqual(hub.liveState(deviceId: "phone").incomingCall?.phoneNumber, "+1555")
        _ = try hub.handle(
            deviceId: "phone",
            .callLogInfo(
                CallLogInfo(callLogId: 7, phoneNumber: "+1555", timestampMillis: 1, durationSeconds: 0, callType: .missed)
            )
        )
        XCTAssertEqual(try hub.callLogs(deviceId: "phone").first?.callType, .missed)
        _ = try hub.handle(deviceId: "phone", .callInfo(CallInfo(callState: .inProgress, phoneNumber: "+1555")))
        XCTAssertNil(hub.liveState(deviceId: "phone").incomingCall)
    }

    func testSmsConversationAndSend() throws {
        let hub = try makeHub()
        let conversation = ConversationInfo(
            infoType: .new,
            threadId: 44,
            recipients: ["+1555"],
            messages: [
                TextMessage(uniqueId: 1, addresses: ["+1555"], threadId: 44, body: "hi", timestamp: 10, messageType: 1, isTextMessage: true),
            ]
        )
        _ = try hub.handle(deviceId: "phone", .conversationInfo(conversation))
        XCTAssertEqual(try hub.conversations(deviceId: "phone").first?.lastMessage, "hi")
        XCTAssertEqual(try hub.messages(deviceId: "phone", threadId: 44).first?.body, "hi")

        let outbound = hub.sendSms(threadId: 44, addresses: ["+1555"], body: "reply")
        guard case .textMessage(let sent) = outbound else { return XCTFail("sms") }
        XCTAssertEqual(sent.body, "reply")
        XCTAssertEqual(sent.messageType, 2)
        XCTAssertEqual(sent.threadId, 44)

        _ = try hub.handle(
            deviceId: "phone",
            .conversationInfo(
                ConversationInfo(
                    infoType: .activeUpdated,
                    threadId: 44,
                    recipients: [],
                    messages: [
                        TextMessage(uniqueId: 2, addresses: ["+1555"], threadId: 44, body: "later", timestamp: 20, messageType: 1),
                    ]
                )
            )
        )
        XCTAssertEqual(try hub.conversations(deviceId: "phone").first?.addresses, ["+1555"])
        XCTAssertEqual(try hub.conversations(deviceId: "phone").first?.lastMessage, "later")
    }

    func testDeviceRailAndActionDispatch() throws {
        let hub = try makeHub()
        hub.actionsCatalog = [ActionItem(id: "lock", name: "Lock", actionId: "power", settings: ["powerKind": "Lock"])]
        _ = try hub.handle(deviceId: "phone", .batteryState(BatteryState(batteryLevel: 18, isCharging: false)))
        _ = try hub.handle(deviceId: "phone", .ringerModeState(RingerModeState(mode: 1)))
        _ = try hub.handle(deviceId: "phone", .dndState(DndState(isEnabled: true)))
        _ = try hub.handle(
            deviceId: "phone",
            .playbackInfo(PlaybackInfo(infoType: .playbackInfo, source: "spotify", trackTitle: "Song", isPlaying: true))
        )
        _ = try hub.handle(deviceId: "phone", .playSound(PlaySound(isPlaying: true)))
        let actionResult = try hub.handle(deviceId: "phone", .actionInfo(ActionInfo(actionId: "lock", actionName: "Lock")))
        _ = try hub.handle(deviceId: "phone", .audioStreamState(AudioStreamState(streamType: .media, level: 40)))
        _ = try hub.handle(deviceId: "phone", .audioStreamState(AudioStreamState(streamType: .ring, level: 12)))
        let state = hub.liveState(deviceId: "phone")
        XCTAssertEqual(state.battery?.batteryLevel, 18)
        XCTAssertEqual(state.ringerMode, 1)
        XCTAssertEqual(state.dndEnabled, true)
        XCTAssertEqual(state.playback.first?.trackTitle, "Song")
        XCTAssertTrue(state.soundPlaying)
        XCTAssertEqual(state.lastAction?.kind, "power")
        XCTAssertEqual(state.lastAction?.command, "/usr/bin/osascript")
        XCTAssertEqual(state.audioStreams[.media], 40)
        XCTAssertEqual(state.audioStreams[.ring], 12)
        guard case .executeAction(let execution) = actionResult.effects.first else {
            return XCTFail("expected executeAction effect")
        }
        XCTAssertEqual(execution.command, "/usr/bin/osascript")
        XCTAssertFalse(execution.command.contains("CGSession"))
    }

    func testDeviceControlOutboundRingerVolumeMediaAndFindPhone() throws {
        let hub = try makeHub()

        let ringer = hub.setRingerMode(0)
        guard case .ringerModeState(let payload) = ringer else { return XCTFail("ringer") }
        XCTAssertEqual(payload.mode, 0)
        let ringerJSON = try JSONSerialization.jsonObject(with: NDJSONCodec.encodeMessage(ringer)) as? [String: Any]
        XCTAssertEqual(ringerJSON?["type"] as? String, "RingerModeState")
        XCTAssertEqual(ringerJSON?["mode"] as? Int, 0)
        XCTAssertEqual(try NDJSONCodec.decodeMessage(from: NDJSONCodec.encodeMessage(ringer)), ringer)

        let volume = hub.setAudioLevel(.media, level: 77)
        guard case .audioStreamState(let stream) = volume else { return XCTFail("volume") }
        XCTAssertEqual(stream.streamType, .media)
        XCTAssertEqual(stream.level, 77)
        let volumeJSON = try JSONSerialization.jsonObject(with: NDJSONCodec.encodeMessage(volume)) as? [String: Any]
        XCTAssertEqual(volumeJSON?["type"] as? String, "AudioStreamState")
        XCTAssertEqual(volumeJSON?["streamType"] as? Int, 3)
        XCTAssertNotEqual(volumeJSON?["streamType"] as? String, "Media")
        XCTAssertEqual(try NDJSONCodec.decodeMessage(from: NDJSONCodec.encodeMessage(volume)), volume)

        let clamped = hub.setAudioLevel(.alarm, level: 140)
        guard case .audioStreamState(let alarm) = clamped else { return XCTFail("clamp") }
        XCTAssertEqual(alarm.level, 100)

        let play = hub.mediaAction(.play, source: "spotify")
        let playJSON = try JSONSerialization.jsonObject(with: NDJSONCodec.encodeMessage(play)) as? [String: Any]
        XCTAssertEqual(playJSON?["type"] as? String, "MediaAction")
        XCTAssertEqual(playJSON?["actionType"] as? String, "Play")
        XCTAssertEqual(playJSON?["source"] as? String, "spotify")
        XCTAssertEqual(try NDJSONCodec.decodeMessage(from: NDJSONCodec.encodeMessage(play)), play)

        let mediaVolume = hub.mediaAction(.volumeUpdate, source: "spotify", value: 55)
        guard case .mediaAction(let media) = mediaVolume else { return XCTFail("media volume") }
        XCTAssertEqual(media.actionType, .volumeUpdate)
        XCTAssertEqual(media.value, 55)

        let find = hub.playSound(isPlaying: true)
        guard case .playSound(let sound) = find else { return XCTFail("find") }
        XCTAssertTrue(sound.isPlaying)
        XCTAssertEqual(try NDJSONCodec.decodeMessage(from: NDJSONCodec.encodeMessage(find)), find)

        let clip = hub.clipboard(type: "text/plain", content: "from-mac")
        guard case .clipboardInfo(let info) = clip else { return XCTFail("clipboard") }
        XCTAssertEqual(info.clipboardType, "text/plain")
        XCTAssertEqual(info.content, "from-mac")
    }

    private func makeHub() throws -> FeatureHub {
        FeatureHub(database: try AppDatabase(inMemory: ()))
    }
}
