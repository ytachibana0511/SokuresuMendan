import AppKit
import Foundation

final class PanicHotkeyManager {
    private var globalMonitor: Any?
    private var localMonitor: Any?

    func startListening(onTrigger: @escaping () -> Void) {
        stopListening()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            Self.handle(event: event, onTrigger: onTrigger)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handle(event: event, onTrigger: onTrigger)
            return event
        }
    }

    func stopListening() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private static func handle(event: NSEvent, onTrigger: @escaping () -> Void) {
        guard event.modifierFlags.contains([.option, .command]),
              event.charactersIgnoringModifiers?.lowercased() == "h"
        else {
            return
        }
        onTrigger()
    }
}
