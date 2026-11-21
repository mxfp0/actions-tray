import AppKit
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate, Sendable {
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func activate() {
        guard let center else { return }
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func runFinished(_ run: WorkflowRun, repo: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(run.workflowName) \(Self.verb(for: run.state))"
        content.subtitle = [repo, run.headBranch].compactMap(\.self).joined(separator: " · ")
        content.body = run.displayTitle
        content.userInfo = ["url": run.htmlUrl.absoluteString]
        if run.state == .failure {
            content.sound = .default
        }
        let id = "run-\(run.id)-\(run.updatedAt.timeIntervalSince1970)"
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link)
        else { return }
        await MainActor.run { _ = NSWorkspace.shared.open(url) }
    }

    private static func verb(for state: RunState) -> String {
        switch state {
        case .success: "succeeded"
        case .failure: "failed"
        case .cancelled: "was cancelled"
        case .actionRequired: "needs attention"
        default: "finished"
        }
    }
}
