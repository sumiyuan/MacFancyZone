import Testing
import Foundation
@testable import ZonesCore

@Suite struct PresetStoreTests {
    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func mutate(_ any: Any, _ overrides: [String: Any]) -> Any {
        if let dict = any as? [String: Any] {
            var out: [String: Any] = [:]
            for (k, v) in dict { out[k] = overrides[k] ?? mutate(v, overrides) }
            return out
        }
        if let arr = any as? [Any] { return arr.map { mutate($0, overrides) } }
        return any
    }

    @Test func missingFileIsFirstLaunch() throws {
        try withTempDir { dir in
            let result = PresetStore(directory: dir).load()
            #expect(result == .firstLaunch(.initial()))
        }
    }

    @Test func saveThenLoadRoundTrips() throws {
        try withTempDir { dir in
            let store = PresetStore(directory: dir)
            var state = ZonesState.initial()
            let custom = Preset(id: UUID(), name: "Custom",
                                layout: .split(direction: .horizontal, ratio: 0.4, first: .zone, second: .zone),
                                spacing: 12, outerGap: false)
            state.upsert(custom)
            state.setActive(custom.id, forDisplay: "A")
            state.setActive(state.presets[1].id, forDisplay: "B")
            try store.save(state)
            #expect(store.load() == .loaded(state))
        }
    }

    @Test func saveCreatesMissingDirectory() throws {
        try withTempDir { dir in
            let nested = dir.appendingPathComponent("nested", isDirectory: true)
            let store = PresetStore(directory: nested)
            try store.save(.initial())
            #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("zones.json").path))
        }
    }

    @Test func corruptFileIsMovedAsideNotOverwritten() throws {
        try withTempDir { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent("zones.json")
            let original = Data("{not json".utf8)
            try original.write(to: file)
            guard case let .recoveredFromCorruptFile(state, movedTo) = PresetStore(directory: dir).load() else {
                Issue.record("expected recoveredFromCorruptFile"); return
            }
            #expect(state == .initial())
            #expect(movedTo.lastPathComponent.hasPrefix("zones.corrupt-"))
            #expect(movedTo.pathExtension == "json")
            #expect(try Data(contentsOf: movedTo) == original)
            #expect(!FileManager.default.fileExists(atPath: file.path))
        }
    }

    @Test func loadSanitizesOutOfRangeValues() throws {
        try withTempDir { dir in
            let store = PresetStore(directory: dir)
            try store.save(.initial())
            let file = dir.appendingPathComponent("zones.json")
            let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            let bad = mutate(obj, ["ratio": 3.0, "spacing": 999.0])
            try JSONSerialization.data(withJSONObject: bad).write(to: file)
            let loaded = store.load().state
            #expect(loaded.presets.allSatisfy { $0.spacing == 64 })
            #expect(loaded.presets[0].layout == .split(direction: .vertical, ratio: 0.95, first: .zone, second: .zone))
        }
    }

    @Test func emptyPresetsArrayLoadsAsStarters() throws {
        try withTempDir { dir in
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(#"{"version":1,"presets":[],"assignments":{}}"#.utf8)
                .write(to: dir.appendingPathComponent("zones.json"))
            let result = PresetStore(directory: dir).load()
            guard case .loaded(let s) = result else { Issue.record("expected loaded"); return }
            #expect(s.presets == StarterPresets.all)
        }
    }
}
