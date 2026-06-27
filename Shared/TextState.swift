import Foundation
import Combine

/// Thread-safe, observable store for the PiP display text.
/// All writes are dispatched to the main actor; observers on any thread are safe.
@MainActor
final class TextState: ObservableObject {
    static let shared = TextState()

    @Published private(set) var text: String = "Ready"

    private init() {}

    func update(_ newText: String) {
        text = newText
        // Also write to shared UserDefaults so App Intents (running in extension
        // process) can hand off text to the main app via Darwin notifications.
        UserDefaults(suiteName: AppGroup.id)?.set(newText, forKey: AppGroup.textKey)
        DarwinNotifier.post(.textDidChange)
    }
}

/// App Group constants — must match the group you create in Xcode → Signing & Capabilities.
enum AppGroup {
    static let id      = "group.com.yourteam.PiPTextDisplay"
    static let textKey = "pipText"
}
