import AppKit
import ZonesCore

@MainActor
enum ScreenIdentity {
    /// Display UUID string via CGDisplayCreateUUIDFromDisplayID.
    static func uuid(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let str = CFUUIDCreateString(nil, cfUUID) as String?
        else { return "unknown-\(screen.localizedName)" }
        return str
    }

    static func monitors() -> [(info: MonitorInfo, screen: NSScreen)] {
        NSScreen.screens.map { (MonitorInfo(id: uuid(for: $0), name: $0.localizedName), $0) }
    }
}
