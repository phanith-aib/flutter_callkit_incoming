import AVFoundation

import Flutter

// ============================================================================
// CallKit REMOVED.
//
// Why: Apple's PushKit VoIP entitlement normally REQUIRES that any VoIP push
// immediately trigger a CallKit report (reportNewIncomingCall), or the OS
// kills the app for violating the "PushKit must report to CallKit" rule.
// Since CallKit itself is gone here, this plugin can no longer be woken by
// PKPushTypeVoIP pushes for incoming calls — incoming-call signaling has to
// come from a normal remote (APNs) push instead, and the "incoming call" UI
// is now rendered entirely by the Flutter side (via the event channel) plus
// an optional local UNNotification banner. There is no more system
// lock-screen call UI, and no more Accept/Decline buttons from iOS itself —
// two new method-channel entry points (`acceptCall`, `declineCall`) replace
// what used to arrive as CXAnswerCallAction / CXEndCallAction from the OS.
//
// Files this does NOT include, but that almost certainly also import
// CallKit and need matching edits:
//   - CallManager.swift   (likely wraps CXCallController / CXTransaction)
//   - Call.swift          (methods like startCall/ansCall probably assumed
//                          the AVAudioSession came from a CXProvider
//                          didActivate callback — here it's passed directly
//                          from AVAudioSession.sharedInstance())
//   - CallkitIncomingAppDelegate protocol (onAccept/onDecline/onEnd/onTimeOut
//                          signatures likely take a CXAction parameter that
//                          no longer exists — signatures below assume it's
//                          been dropped)
//   - The Dart-side plugin class needs `acceptCall` / `declineCall` methods
//     added, and your custom incoming-call UI needs to call them instead of
//     relying on the system CallKit UI.
// ============================================================================

import UIKit

import UserNotifications

@available(iOS 10.0, *)
public class SwiftFlutterCallkitIncomingPlugin: NSObject, FlutterPlugin {

    static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP =
        "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"

    static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
    static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
    static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
    static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
    static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
    static let ACTION_CALL_CALLBACK = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK"
    static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"
    static let ACTION_CALL_CONNECTED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CONNECTED"

    static let ACTION_CALL_TOGGLE_HOLD =
        "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
    static let ACTION_CALL_TOGGLE_MUTE =
        "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
    static let ACTION_CALL_TOGGLE_DMTF =
        "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
    static let ACTION_CALL_TOGGLE_GROUP =
        "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
    static let ACTION_CALL_TOGGLE_AUDIO_SESSION =
        "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"

    @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!

    private var streamHandlers: WeakArray<EventCallbackHandler> = WeakArray([])

    private var outgoingCall: Call?
    private var answerCall: Call?

    private var data: Data?
    private var isFromPushKit: Bool = false
    private var silenceEvents: Bool = false
    private let devicePushTokenVoIP = "DevicePushTokenVoIP"

    private func sendEvent(_ event: String, _ body: [String: Any?]?) {
        if silenceEvents {
            print(event, " silenced")
            return
        } else {
            streamHandlers.reap().forEach { handler in
                handler?.send(event, body ?? [:])
            }
        }
    }

    @objc public func sendEventCustom(_ event: String, body: NSDictionary?) {
        streamHandlers.reap().forEach { handler in
            handler?.send(event, body ?? [:])
        }
    }

    public static func sharePluginWithRegister(with registrar: FlutterPluginRegistrar) {
        if sharedInstance == nil {
            sharedInstance = SwiftFlutterCallkitIncomingPlugin(messenger: registrar.messenger())
        }
        sharedInstance.shareHandlers(with: registrar)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        sharePluginWithRegister(with: registrar)
    }

    private static func createMethodChannel(messenger: FlutterBinaryMessenger)
        -> FlutterMethodChannel
    {
        return FlutterMethodChannel(name: "flutter_callkit_incoming", binaryMessenger: messenger)
    }

    private static func createEventChannel(messenger: FlutterBinaryMessenger) -> FlutterEventChannel
    {
        return FlutterEventChannel(
            name: "flutter_callkit_incoming_events", binaryMessenger: messenger)
    }

    public init(messenger: FlutterBinaryMessenger) {
        // CallManager removed
    }

    private func shareHandlers(with registrar: FlutterPluginRegistrar) {
        registrar.addMethodCallDelegate(
            self, channel: Self.createMethodChannel(messenger: registrar.messenger()))
        let eventsHandler = EventCallbackHandler()
        self.streamHandlers.append(eventsHandler)
        Self.createEventChannel(messenger: registrar.messenger()).setStreamHandler(eventsHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showCallkitIncoming":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                self.data = Data(args: getArgs)
                showCallkitIncoming(self.data!, fromPushKit: false)
            }
            result(true)
            break
        case "showMissCallNotification":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                self.data = Data(args: getArgs)
                self.showMissedCallNotification(data!)
            }
            result(true)
            break
        case "startCall":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                self.data = Data(args: getArgs)
                self.startCall(self.data!, fromPushKit: false)
            }
            result(true)
            break
        case "endCall":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if self.isFromPushKit {
                self.endCall(self.data!)
            } else {
                if let getArgs = args as? [String: Any] {
                    self.data = Data(args: getArgs)
                    self.endCall(self.data!)
                }
            }
            result(true)
            break
        case "acceptCall":
            guard let args = call.arguments as? [String: Any] else {
                result(true)
                return
            }
            self.acceptCall(Data(args: args))
            result(true)
            break
        case "declineCall":
            guard let args = call.arguments as? [String: Any] else {
                result(true)
                return
            }
            self.endCall(Data(args: args))
            result(true)
            break
        case "muteCall":
            guard let args = call.arguments as? [String: Any],
                let callId = args["id"] as? String,
                let isMuted = args["isMuted"] as? Bool
            else {
                result(true)
                return
            }

            self.muteCall(callId, isMuted: isMuted)
            result(true)
            break
        case "isMuted":
            guard let args = call.arguments as? [String: Any],
                let callId = args["id"] as? String
            else {
                result(false)
                return
            }
            // CallManager removed - return false
            result(false)
            break
        case "holdCall":
            guard let args = call.arguments as? [String: Any],
                let callId = args["id"] as? String,
                let onHold = args["isOnHold"] as? Bool
            else {
                result(true)
                return
            }
            self.holdCall(callId, onHold: onHold)
            result(true)
            break
        case "callConnected":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if self.isFromPushKit {
                self.connectedCall(self.data!)
            } else {
                if let getArgs = args as? [String: Any] {
                    self.data = Data(args: getArgs)
                    self.connectedCall(self.data!)
                }
            }
            result(true)
            break
        case "activeCalls":
            result([])
            break
        case "endAllCalls":
            result(true)
            break
        case "getDevicePushTokenVoIP":
            result(self.getDevicePushTokenVoIP())
            break
        case "silenceEvents":
            guard let silence = call.arguments as? Bool else {
                result(true)
                return
            }

            self.silenceEvents = silence
            result(true)
            break
        case "requestNotificationPermission":
            guard let args = call.arguments else {
                result(true)
                return
            }
            if let getArgs = args as? [String: Any] {
                self.requestNotificationPermission(getArgs)
            }
            result(true)
            break
        case "requestFullIntentPermission":
            result(true)
            break
        case "canUseFullScreenIntent":
            result(true)
            break
        case "hideCallkitIncoming":
            result(true)
            break
        case "endNativeSubsystemOnly":
            result(true)
            break
        case "setAudioRoute":
            result(true)
            break
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    @objc public func setDevicePushTokenVoIP(_ deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: devicePushTokenVoIP)
        self.sendEvent(
            SwiftFlutterCallkitIncomingPlugin.ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP,
            ["deviceTokenVoIP": deviceToken])
    }

    @objc public func getDevicePushTokenVoIP() -> String {
        return UserDefaults.standard.string(forKey: devicePushTokenVoIP) ?? ""
    }

    @objc public func getAcceptedCall() -> Data? {
        NSLog(
            "Call data ids \(String(describing: data?.uuid)) \(String(describing: answerCall?.uuid.uuidString))"
        )
        if data?.uuid.lowercased() == answerCall?.uuid.uuidString.lowercased() {
            return data
        }
        return nil
    }

    @objc public func showCallkitIncoming(
        _ data: Data, fromPushKit: Bool, onError: ((Error?) -> Void)? = nil
    ) {
        self.isFromPushKit = fromPushKit
        if fromPushKit {
            self.data = data
        }

        if data.isShowMissedCallNotification {
            CallkitNotificationManager.shared.addNotificationCategory(
                data.missedNotificationCallbackText)
        }

        guard let uuid = UUID(uuidString: data.uuid) else {
            NSLog("[CallkitIncoming] showCallkitIncoming: invalid UUID '\(data.uuid)' — ignored")
            onError?(nil)
            return
        }

        configureAudioSession()
        let call = Call(uuid: uuid, data: data)
        call.handle = data.handle
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
        self.endCallNotExist(data)
    }

    @objc public func showCallkitIncoming(_ data: Data, fromPushKit: Bool) {
        self.showCallkitIncoming(data, fromPushKit: fromPushKit, onError: nil)
    }

    @objc public func showCallkitIncoming(
        _ data: Data, fromPushKit: Bool, completion: @escaping () -> Void
    ) {
        self.showCallkitIncoming(data, fromPushKit: fromPushKit, onError: nil)
        completion()
    }

    @objc public func startCall(_ data: Data, fromPushKit: Bool) {
        self.isFromPushKit = fromPushKit
        if fromPushKit {
            self.data = data
        }
        guard let uuid = UUID(uuidString: data.uuid) else {
            NSLog("[CallkitIncoming] startCall: invalid UUID '\(data.uuid)' — ignored")
            return
        }

        let call = Call(uuid: uuid, data: data, isOutGoing: true)
        call.handle = data.handle
        self.configureAudioSession()
        self.outgoingCall = call
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_START, data.toJSON())

        call.startCall(withAudioSession: AVAudioSession.sharedInstance()) { success in
            if success {
                call.startAudio()
            }
        }
        sendDefaultAudioInterruptionNotificationToStartAudioResource()
    }

    @objc public func acceptCall(_ data: Data) {
        guard let uuid = UUID(uuidString: data.uuid) else {
            NSLog("[CallkitIncoming] acceptCall: no call for uuid '\(data.uuid)' — ignored")
            return
        }

        self.configureAudioSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1200)) {
            self.configureAudioSession()
        }

        let call = Call(uuid: uuid, data: data)
        call.data.isAccepted = true
        self.answerCall = call
        self.data = call.data

        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, call.data.toJSON())

        call.ansCall(withAudioSession: AVAudioSession.sharedInstance()) { success in
            if success {
                call.startAudio()
            }
        }
        sendDefaultAudioInterruptionNotificationToStartAudioResource()

        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onAccept(call)
        }
    }

    @objc public func muteCall(_ callId: String, isMuted: Bool) {
        // CallManager removed - mute functionality handled elsewhere
        self.sendMuteEvent(callId, isMuted)
    }

    @objc public func holdCall(_ callId: String, onHold: Bool) {
        // CallManager removed - hold functionality handled elsewhere
        self.sendHoldEvent(callId, onHold)
    }

    @objc public func endCall(_ data: Data) {
        let uuidSourceString: String
        if self.isFromPushKit {
            guard let stored = self.data else {
                NSLog("[CallkitIncoming] endCall: PushKit branch but self.data is nil — ignored")
                return
            }
            uuidSourceString = stored.uuid
            self.isFromPushKit = false
        } else {
            uuidSourceString = data.uuid
        }

        guard let uuid = UUID(uuidString: uuidSourceString) else {
            NSLog("[CallkitIncoming] endCall: invalid UUID '\(uuidSourceString)' — ignored")
            return
        }

        let call = Call(uuid: uuid, data: data)

        if self.answerCall == nil && self.outgoingCall == nil {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_DECLINE, data.toJSON())
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onDecline(call)
            }
        } else {
            self.answerCall = nil
            self.outgoingCall = nil
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data.toJSON())
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onEnd(call)
            }
        }
    }

    @objc public func connectedCall(_ data: Data) {
        let uuidSourceString: String
        if self.isFromPushKit {
            guard let stored = self.data else {
                NSLog(
                    "[CallkitIncoming] connectedCall: PushKit branch but self.data is nil — ignored"
                )
                return
            }
            uuidSourceString = stored.uuid
            self.isFromPushKit = false
        } else {
            uuidSourceString = data.uuid
        }
        guard let uuid = UUID(uuidString: uuidSourceString) else {
            NSLog("[CallkitIncoming] connectedCall: invalid UUID '\(uuidSourceString)' — ignored")
            return
        }
        let call = Call(uuid: uuid, data: data)
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_CONNECTED, data.toJSON())
    }

    @objc public func activeCalls() -> [[String: Any]] {
        return []
    }

    @objc public func endAllCalls() {
        self.isFromPushKit = false
    }

    func endCallNotExist(_ data: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(data.duration)) {
            guard let uuid = UUID(uuidString: data.uuid) else {
                NSLog("[CallkitIncoming] endCallNotExist: invalid UUID '\(data.uuid)' — ignored")
                return
            }
            if self.answerCall == nil && self.outgoingCall == nil {
                self.callEndTimeout(data)
            }
        }
    }

    func callEndTimeout(_ data: Data) {
        guard let uuid = UUID(uuidString: data.uuid) else {
            NSLog("[CallkitIncoming] callEndTimeout: invalid UUID '\(data.uuid)' — ignored")
            return
        }
        let call = Call(uuid: uuid, data: data)
        self.showMissedCallNotification(data)
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
    }

    func sendDefaultAudioInterruptionNotificationToStartAudioResource() {
        var userInfo: [AnyHashable: Any] = [:]
        let intrepEndeRaw = AVAudioSession.InterruptionType.ended.rawValue
        userInfo[AVAudioSessionInterruptionTypeKey] = intrepEndeRaw
        userInfo[AVAudioSessionInterruptionOptionKey] =
            AVAudioSession.InterruptionOptions.shouldResume.rawValue
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: self, userInfo: userInfo)
    }

    func configureAudioSession() {
        if data?.configureAudioSession != false {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(
                    AVAudioSession.Category.playAndRecord,
                    options: [
                        .allowBluetoothA2DP,
                        .duckOthers,
                        .allowBluetooth,
                    ])

                try session.setMode(self.getAudioSessionMode(data?.audioSessionMode))
                try session.setActive(data?.audioSessionActive ?? true)
                try session.setPreferredSampleRate(data?.audioSessionPreferredSampleRate ?? 44100.0)
                try session.setPreferredIOBufferDuration(
                    data?.audioSessionPreferredIOBufferDuration ?? 0.005)
            } catch {
                print(error)
            }

            self.sendEvent(
                SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION,
                ["isActive": true])
        }
    }

    func getAudioSessionMode(_ audioSessionMode: String?) -> AVAudioSession.Mode {
        var mode = AVAudioSession.Mode.default
        switch audioSessionMode {
        case "gameChat":
            mode = AVAudioSession.Mode.gameChat
            break
        case "measurement":
            mode = AVAudioSession.Mode.measurement
            break
        case "moviePlayback":
            mode = AVAudioSession.Mode.moviePlayback
            break
        case "spokenAudio":
            mode = AVAudioSession.Mode.spokenAudio
            break
        case "videoChat":
            mode = AVAudioSession.Mode.videoChat
            break
        case "videoRecording":
            mode = AVAudioSession.Mode.videoRecording
            break
        case "voiceChat":
            mode = AVAudioSession.Mode.voiceChat
            break
        case "voicePrompt":
            if #available(iOS 12.0, *) {
                mode = AVAudioSession.Mode.voicePrompt
            } else {
                // Fallback on earlier versions
            }
            break
        default:
            mode = AVAudioSession.Mode.default
        }
        return mode
    }

    private func sendMuteEvent(_ id: String, _ isMuted: Bool) {
        self.sendEvent(
            SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_MUTE,
            ["id": id, "isMuted": isMuted])
    }

    private func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
        self.sendEvent(
            SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_HOLD,
            ["id": id, "isOnHold": isOnHold])
    }

    @objc public func sendCallbackEvent(_ data: [String: Any]?) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_CALLBACK, data)
    }

    private func requestNotificationPermission(_ map: [String: Any]) {
        CallkitNotificationManager.shared.requestNotificationPermission(map)
    }

    private func showMissedCallNotification(_ data: Data) {
        if !data.isShowMissedCallNotification {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "\(data.nameCaller)"
        content.body = "\(data.missedNotificationSubtitle)"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "MISSED_CALL_CATEGORY"
        content.userInfo = data.toJSON()

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: data.uuid,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling missed call notification: \(error)")
            } else {
                print("Missed call notification scheduled.")
            }
        }
    }

}
class EventCallbackHandler: NSObject, FlutterStreamHandler {
    private var eventSink: FlutterEventSink?

    public func send(_ event: String, _ body: Any) {
        let data: [String: Any] = [
            "event": event,
            "body": body,
        ]
        eventSink?(data)
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError?
    {
        self.eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
@available(iOS 10.0, *)
@objc(FlutterCallkitIncomingPlugin)
public class FlutterCallkitIncomingPlugin: NSObject, FlutterPlugin {
    @objc public static func register(with registrar: FlutterPluginRegistrar) {
        SwiftFlutterCallkitIncomingPlugin.register(with: registrar)
    }
}
