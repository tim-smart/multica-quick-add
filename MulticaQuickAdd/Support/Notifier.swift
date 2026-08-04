import Foundation
import UserNotifications

enum Notifier {
  static func requestAuthorization() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
  }

  static func notify(title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = String(body.prefix(200))
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }
}
