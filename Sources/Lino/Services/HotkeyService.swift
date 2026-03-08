import Foundation
import HotKey
import Carbon

@Observable
@MainActor
final class HotkeyService {
    private var hotKey: HotKey?

    func register(onTrigger: @escaping @MainActor () -> Void) {
        // Cmd+Shift+L
        hotKey = HotKey(key: .l, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = {
            onTrigger()
        }
    }

    func unregister() {
        hotKey = nil
    }
}
