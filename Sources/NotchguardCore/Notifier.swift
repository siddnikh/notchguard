import Foundation
import UserNotifications

public protocol NotificationSending: Sendable {
    func send(_ event: AgentEvent)
}

public final class NativeNotifier: NSObject, NotificationSending, UNUserNotificationCenterDelegate, @unchecked Sendable {
    public static let shared = NativeNotifier()

    public func prepare() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    public func send(_ event: AgentEvent) {
        NotchOverlay.shared.show(event)
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.summary.prefix(220).description
        content.sound = .default
        content.categoryIdentifier = "NOTCHGUARD_AGENT"
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        // The system banner is the accessible fallback when a notch panel is
        // hidden by full-screen work or a display does not have a camera housing.
        UNUserNotificationCenter.current().add(request)
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

public enum TerminalJumper {
    public static func jump(to directory: URL) throws {
        let script = """
        on run argv
            tell application "Terminal"
                activate
                do script "cd " & quoted form of item 1 of argv in front window
            end tell
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, directory.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallback.arguments = ["-a", "Terminal", directory.path]
            try fallback.run()
        }
    }

}
