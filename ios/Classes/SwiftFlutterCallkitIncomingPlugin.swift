import Flutter
import UIKit
import AVFoundation
import UserNotifications

@available(iOS 10.0, *)
public class SwiftFlutterCallkitIncomingPlugin: NSObject, FlutterPlugin {
    
    static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP = "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"
    
    static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
    static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
    static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
    static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
    static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
    static let ACTION_CALL_CALLBACK = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK"
    static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"
    static let ACTION_CALL_CONNECTED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CONNECTED"
    
    static let ACTION_CALL_TOGGLE_HOLD = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
    static let ACTION_CALL_TOGGLE_MUTE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
    static let ACTION_CALL_TOGGLE_DMTF = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
    static let ACTION_CALL_TOGGLE_GROUP = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
    static let ACTION_CALL_TOGGLE_AUDIO_SESSION = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"
    
    @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!
    
    private var streamHandlers: WeakArray<EventCallbackHandler> = WeakArray([])

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_callkit_incoming", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterCallkitIncomingPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        SwiftFlutterCallkitIncomingPlugin.sharedInstance = instance
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "showCallkitIncoming":
            result(true)
        case "showMissCallNotification":
            result(true)
        case "startCall":
            result(true)
        case "endCall":
            result(true)
        case "muteCall":
            result(true)
        case "isMuted":
            result(false)
        case "holdCall":
            result(true)
        case "callConnected":
            result(true)
        case "activeCalls":
            result([])
        case "endAllCalls":
            result(true)
        case "getDevicePushTokenVoIP":
            result("")
        case "silenceEvents":
            result(true)
        case "requestNotificationPermission":
            result(true)
        case "requestFullIntentPermission":
            result(true)
        case "canUseFullScreenIntent":
            result(true)
        case "hideCallkitIncoming":
            result(true)
        case "endNativeSubsystemOnly":
            result(true)
        case "setAudioRoute":
            result(true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
    }
    
    @objc public func sendCallbackEvent(_ data: [String: Any]?) {
    }
    
    
    private func requestNotificationPermission(_ map: [String: Any]) {
        CallkitNotificationManager.shared.requestNotificationPermission(map)
    }
    
    
    private func showMissedCallNotification(_ data: Data) {
        if(!data.isShowMissedCallNotification){
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
        let data: [String : Any] = [
            "event": event,
            "body": body
        ]
        eventSink?(data)
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
