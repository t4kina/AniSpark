import EventKit
import EventKitUI
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CalendarEventPlugin") {
      CalendarEventPlugin.register(with: registrar)
    }
  }
}

/// Opens the system's "new event" sheet filled in with an event from
/// lib/services/device_calendar.dart. Answers true once the event is saved,
/// false when it's cancelled or calendar access is denied (before iOS 17).
/// It lives here rather than in its own file so the Xcode project needs no
/// new file reference.
final class CalendarEventPlugin: NSObject, FlutterPlugin, EKEventEditViewDelegate {
  private let eventStore = EKEventStore()
  // The sheet's answer, until it closes. iOS shows one sheet at a time.
  private var pendingResult: FlutterResult?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "anispark/calendar", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(CalendarEventPlugin(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "addEvent" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let start = (args["start"] as? NSNumber)?.doubleValue,
          let end = (args["end"] as? NSNumber)?.doubleValue else {
      result(FlutterError(code: "bad_event", message: "The event has no start or end", details: nil))
      return
    }
    guard pendingResult == nil else {
      result(false)
      return
    }
    pendingResult = result

    let event = EKEvent(eventStore: eventStore)
    event.title = args["title"] as? String
    event.startDate = Date(timeIntervalSince1970: start / 1000)
    event.endDate = Date(timeIntervalSince1970: end / 1000)
    event.notes = args["notes"] as? String
    if let url = args["url"] as? String {
      event.url = URL(string: url)
    }
    if args["alertAtStart"] as? Bool == true {
      event.addAlarm(EKAlarm(relativeOffset: 0))
    }

    if #available(iOS 17, *) {
      // The sheet runs outside the app, so it needs no calendar access.
      present(event)
    } else {
      eventStore.requestAccess(to: .event) { granted, _ in
        DispatchQueue.main.async {
          if granted {
            self.present(event)
          } else {
            self.finish(saved: false)
          }
        }
      }
    }
  }

  private func present(_ event: EKEvent) {
    guard let presenter = topViewController() else {
      finish(saved: false)
      return
    }
    let editor = EKEventEditViewController()
    editor.eventStore = eventStore
    editor.event = event
    editor.editViewDelegate = self
    presenter.present(editor, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  func eventEditViewController(
    _ controller: EKEventEditViewController,
    didCompleteWith action: EKEventEditViewAction
  ) {
    // Answers once the sheet is gone, so another swipe can open a new one.
    controller.dismiss(animated: true) {
      self.finish(saved: action == .saved)
    }
  }

  private func finish(saved: Bool) {
    pendingResult?(saved)
    pendingResult = nil
  }
}
