import Flutter
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let controller = window?.rootViewController as? FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.example.anispark/widget",
      binaryMessenger: controller!.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      if call.method == "updateWidget", let args = call.arguments as? [String: Any] {
        let watching  = args["watching_count"]  as? Int ?? 0
        let completed = args["completed_count"] as? Int ?? 0
        let airing    = args["airing_today"]    as? String ?? ""

        // Write to App Group shared defaults (read by the widget extension)
        if let defaults = UserDefaults(suiteName: "group.com.example.anispark") {
          defaults.set(watching,  forKey: "widget_watching_count")
          defaults.set(completed, forKey: "widget_completed_count")
          defaults.set(airing.isEmpty ? nil : airing, forKey: "widget_airing_today")
        }

        // Tell WidgetKit to reload all timelines
        if #available(iOS 14.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
        }

        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
