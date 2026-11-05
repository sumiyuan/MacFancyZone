import AppKit
import CoreAudio
import Darwin
import MixerCore

/// Finds the apps making sound, keeps a capture running for each app set away from 100%
/// or muted, and publishes rows to `MixerModel`. Runs whether or not the panel is open.
@available(macOS 14.2, *)
@MainActor
final class MixerController {
    private struct Active {
        var capture: AppAudioCapture
        var objects: Set<AudioObjectID>
        var probe: SilenceProbe
    }

    private let model: MixerModel
    private let store: MixerStore
    private var settings = MixerSettings()
    private var sources = SoundSources()
    private var captures: [String: Active] = [:]
    /// Apps whose capture failed or stayed silent; not retried until the panel next opens.
    private var unavailable: Set<String> = []
    /// Owner lookups by pid (nil = untraceable). Pruned to the pids Core Audio still lists.
    private var owners: [Int32: OwningApp?] = [:]
    private var timer: Timer?
    private var pendingSave: DispatchWorkItem?

    init(model: MixerModel, store: MixerStore) {
        self.model = model
        self.store = store
    }

    func start() {
        settings = store.load()
        model.onSetVolume = { [weak self] id, v in self?.change(id) { $0.setVolume(v, for: id) } }
        model.onToggleMute = { [weak self] id in
            guard let self else { return }
            let muted = self.settings.setting(for: id).muted
            self.change(id) { $0.setMuted(!muted, for: id) }
        }
        model.onOpenAudioSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common so it keeps running while a slider is being dragged.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Gives apps that failed one more try.
    func panelOpened() {
        unavailable.removeAll()
        tick()
    }

    /// Stops every capture, so all apps play normally again. Used when quitting.
    func stopAll() {
        timer?.invalidate()
        timer = nil
        for active in captures.values { active.capture.stop() }
        captures.removeAll()
        flushSave()
    }

    // MARK: Polling

    private func tick() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        let me = getpid()
        var processes: [AudioProcess] = []
        for object in caGetArray(system, kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = caGet(object, kAudioProcessPropertyPID, default: -1)
            guard pid > 0, pid != me else { continue }
            let running: UInt32 = caGet(object, kAudioProcessPropertyIsRunningOutput, default: 0)
            processes.append(AudioProcess(objectID: object, pid: pid, isPlaying: running != 0))
        }
        let listed = Set(processes.map(\.pid))
        owners = owners.filter { listed.contains($0.key) }
        sources.update(processes: processes, owner: { [unowned self] in self.owner(of: $0) },
                       now: ProcessInfo.processInfo.systemUptime)
        reconcile()
    }

    private func owner(of pid: Int32) -> OwningApp? {
        if let cached = owners[pid] { return cached }
        let found = resolveOwner(pid: pid, parent: Self.parentPID, app: Self.regularApp)
        owners[pid] = found
        return found
    }

    private nonisolated static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private static func regularApp(_ pid: Int32) -> OwningApp? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier else { return nil }
        return OwningApp(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: pid)
    }

    // MARK: Captures

    /// Starts, rebuilds or stops captures to match the settings, checks silence probes,
    /// and republishes the rows.
    private func reconcile() {
        let now = ProcessInfo.processInfo.systemUptime
        let visible = Set(sources.rows.map(\.bundleID))

        for (id, active) in captures where !wanted(id, visible: visible) {
            active.capture.stop()
            captures[id] = nil
        }

        for id in visible where wanted(id, visible: visible) {
            let objects = Set(sources.processObjects(for: id))
            let gain = settings.setting(for: id).gain
            if let active = captures[id] {
                guard objects != active.objects || currentDevice(for: objects) != active.capture.outputDeviceID else {
                    continue
                }
                // Start the replacement before stopping the old one, so the app never
                // briefly plays at full volume between the two.
                if let fresh = AppAudioCapture(processObjects: Array(objects), gain: gain) {
                    active.capture.stop()
                    captures[id] = Active(capture: fresh, objects: objects, probe: active.probe)
                } else {
                    active.capture.stop()
                    captures[id] = nil
                    unavailable.insert(id)
                }
            } else if let capture = AppAudioCapture(processObjects: Array(objects), gain: gain) {
                captures[id] = Active(capture: capture, objects: objects, probe: SilenceProbe(startedAt: now))
            } else {
                unavailable.insert(id)
            }
        }

        for id in Array(captures.keys) {
            guard var active = captures[id] else { continue }
            let verdict = active.probe.observe(heardSound: active.capture.heardSound,
                                               sourcePlaying: sources.isPlaying(id), now: now)
            captures[id] = active
            switch verdict {
            case .silent:
                active.capture.stop()
                captures[id] = nil
                unavailable.insert(id)
                model.permissionNeeded = true
            case .healthy:
                model.permissionNeeded = false
            case .pending:
                break
            }
        }
        publish()
    }

    private func wanted(_ id: String, visible: Set<String>) -> Bool {
        visible.contains(id) && settings.setting(for: id).needsCapture && !unavailable.contains(id)
    }

    /// The device the app's processes are playing to now, as `AppAudioCapture` would pick it.
    private func currentDevice(for objects: Set<AudioObjectID>) -> AudioObjectID {
        objects.lazy
            .compactMap { caGetArray($0, kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput).first }
            .first
            ?? caGet(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                     default: AudioObjectID(kAudioObjectUnknown))
    }

    private func publish() {
        model.rows = sources.rows.map { app in
            let s = settings.setting(for: app.bundleID)
            return MixerRow(id: app.bundleID, name: app.name,
                            icon: NSRunningApplication(processIdentifier: app.pid)?.icon,
                            volume: s.volume, muted: s.muted,
                            unavailable: unavailable.contains(app.bundleID))
        }
    }

    // MARK: Settings

    private func change(_ id: String, _ edit: (inout MixerSettings) -> Void) {
        edit(&settings)
        captures[id]?.capture.setGain(settings.setting(for: id).gain)
        reconcile()
        scheduleSave()
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flushSave() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    private func flushSave() {
        pendingSave?.cancel()
        pendingSave = nil
        try? store.save(settings)
    }
}
