import Foundation

/// Thin wrapper around Darwin (system-level) notifications.
/// These cross process boundaries, so the App Intents extension can
/// wake the main app even when it's backgrounded.
enum DarwinNotification: String {
    case textDidChange = "com.yourteam.PiPTextDisplay.textDidChange"
    case startPiP      = "com.yourteam.PiPTextDisplay.startPiP"
    case stopPiP       = "com.yourteam.PiPTextDisplay.stopPiP"
}

enum DarwinNotifier {
    static func post(_ note: DarwinNotification) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(note.rawValue as CFString),
            nil, nil, true
        )
    }

    /// Register a callback fired on the main queue when the Darwin notification arrives.
    static func observe(_ note: DarwinNotification, handler: @escaping () -> Void) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name   = note.rawValue as CFString
        CFNotificationCenterAddObserver(
            center, nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async { handler() }
            },
            name, nil, .deliverImmediately
        )
    }
}
