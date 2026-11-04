import Foundation
import Observation
import ZonesCore

enum LaunchState { case on, off, needsApproval }

/// State and action hooks for the menu panel. `AppController` fills this in and wires the actions.
@MainActor @Observable
final class PanelModel {
    var permissionNeeded = false
    var monitors: [MonitorInfo] = []
    var selectedMonitorID: String?
    var tiles: [Preset] = []
    var activePresetID: UUID?
    var switcherOn = true
    var launch: LaunchState = .off

    var onSelectMonitor: (String) -> Void = { _ in }
    var onApplyTile: (UUID) -> Void = { _ in }
    var onNewLayout: () -> Void = {}
    var onEditCurrent: () -> Void = {}
    var onAllLayouts: () -> Void = {}
    var onToggleSwitcher: () -> Void = {}
    var onToggleLaunch: () -> Void = {}
    var onOpenPermissionSettings: () -> Void = {}
    var onQuit: () -> Void = {}
}
