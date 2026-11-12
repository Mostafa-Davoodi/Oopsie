import Foundation
import UserNotifications

/// Posts "machine is ready" notifications. Clicking one opens SSH to that machine.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// Called with the machine name when the user clicks a notification.
    var onOpen: ((String) -> Void)?

    /// UNUserNotificationCenter needs an app bundle; `swift run` has none.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    override init() {
        super.init()
        center?.delegate = self
    }

    func post(title: String, body: String, machine: String) {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.userInfo = ["machine": machine]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let machine = response.notification.request.content.userInfo["machine"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let machine { self.onOpen?(machine) }
            }
            completionHandler()
        }
    }

    /// Show notifications even if Oopsie counts as the active app.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
