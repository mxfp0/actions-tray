import AppKit
import SwiftUI

@main
struct ActionsTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: appDelegate.store)
        } label: {
            StatusLabel(store: appDelegate.store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = RunStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.notifier.activate()
        store.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [store] _ in
            MainActor.assumeIsolated { store.start() }
        }
    }
}

struct StatusLabel: View {
    let store: RunStore

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: Self.icon(for: store.overall))
            if store.activeCount > 0 {
                Text("\(store.activeCount)").monospacedDigit()
            }
        }
    }

    // MenuBarExtra renders SwiftUI images as templates, so colored states need a non-template NSImage.
    private static func icon(for state: RunState?) -> NSImage {
        let (symbol, color): (String, NSColor?) = switch state {
        case nil: ("bolt.horizontal.circle", nil)
        case .success, .skipped, .cancelled: ("checkmark.circle", nil)
        case .running, .queued: ("arrow.triangle.2.circlepath.circle.fill", .systemOrange)
        case .failure: ("xmark.circle.fill", .systemRed)
        case .actionRequired: ("exclamationmark.circle.fill", .systemYellow)
        }
        var config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        if let color {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [.white, color]))
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GitHub Actions status")!
            .withSymbolConfiguration(config)!
        image.isTemplate = color == nil
        return image
    }
}
