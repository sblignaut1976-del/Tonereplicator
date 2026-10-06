import XCTest
@testable import ToneReplicator

final class GearTests: XCTestCase {
    private func record() -> SavedCalibration {
        let id = UUID()
        return SavedCalibration(id: id, createdAt: Date(),
            fingerprint: CalibrationFingerprint(algorithm: "fixture", sampleRate: 44_100,
                frames: 441_000, peak: 0.5, rms: 0.2, dc: 0, bandDB: [Double](repeating: -30, count: 24)),
            wavFilename: "\(id.uuidString).wav", interfaceUID: "fixture-interface", inputChannel: 0,
            context: CaptureContext())
    }
    func testReplacementRequiresExplicitActionAndKeepsHistory() throws {
        var config = GuitarConfiguration(id: UUID(), identity: GuitarIdentity.fenderTemplate())
        let first = record(); let second = record()
        try config.save(first, replacing: false)
        XCTAssertThrowsError(try config.save(second, replacing: false))
        XCTAssertEqual(config.baseTone, first)
        XCTAssertEqual(config.calibrations.count, 1)
        try config.save(second, replacing: true)
        XCTAssertEqual(config.baseTone, second)
        XCTAssertEqual(config.calibrations, [first, second])
        XCTAssertThrowsError(try config.save(second, replacing: true))
    }
    func testPickupConfigurationsAndSourceChoicePersistSeparately() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(url: dir.appendingPathComponent("project.json"))
        var bridge = GuitarConfiguration(id: UUID(), identity: GuitarIdentity.fenderTemplate())
        try bridge.save(record(), replacing: false)
        var neckIdentity = GuitarIdentity.fenderTemplate(); neckIdentity.pickupPosition = "Neck"; neckIdentity.pickupModel = "Unknown"
        var neck = GuitarConfiguration(id: UUID(), identity: neckIdentity)
        try neck.save(record(), replacing: false)
        bridge.activeSource = .factory
        var project = Project(); project.gear = [bridge, neck]; project.selectedGuitarID = bridge.id
        try store.save(project)
        let loaded = try store.load()
        XCTAssertEqual(loaded, project)
        XCTAssertEqual(loaded.gear[0].activeSource, .factory)
        XCTAssertNotEqual(loaded.gear[0].activeCalibrationID, loaded.gear[1].activeCalibrationID)
        XCTAssertEqual(loaded.gear[0].baseTone, bridge.baseTone)
    }
    func testSchemaOneMigrationPreservesRoutingAndBacksUpOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(url: dir.appendingPathComponent("project.json"))
        var old = Project(); old.selectedInterfaceUID = "fixture-interface"
        var route = RoutingPreset(); route.inputUID = "fixture-interface"; route.inputChannel = 1
        old.routingByInterface[old.selectedInterfaceUID] = route
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        object["schemaVersion"] = 1; object.removeValue(forKey: "gear"); object.removeValue(forKey: "selectedGuitarID")
        let original = try JSONSerialization.data(withJSONObject: object)
        try original.write(to: store.url)
        let loaded = try store.load()
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.routingByInterface, old.routingByInterface)
        XCTAssertEqual(try Data(contentsOf: store.url), original) // Loading alone never migrates disk.
        try store.save(loaded)
        let backups = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("project-schema1-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        try store.save(loaded)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("project-schema1-") }.count, 1)
    }
    func testSaveDoesNotOverwriteNewerProject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(url: dir.appendingPathComponent("project.json"))
        let original = Data("{\"schemaVersion\":99,\"analysisRate\":44100}".utf8)
        try original.write(to: store.url)
        XCTAssertThrowsError(try store.save(Project()))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }
    func testMeasuredCaptureAndWaveFormat() throws {
        let samples: [Float] = (0..<441_000).map { 0.25 * Float(sin(2 * Double.pi * 1000 * Double($0) / 44_100)) }
        let draft = try CalibrationAnalyzer.analyze(samples: samples, guitarID: UUID(), route: RoutingPreset(),
            context: CaptureContext(path: .direct), lostFrames: false, invalidSamples: false)
        XCTAssertEqual(draft.record.fingerprint.sampleRate, 44_100)
        XCTAssertEqual(draft.record.fingerprint.bandDB.count, 24)
        XCTAssertEqual(draft.record.fingerprint.rms, 0.25 / sqrt(2), accuracy: 0.00001)
        XCTAssertEqual(draft.wav.count, 56 + 441_000 * 4)
        XCTAssertEqual(String(data: draft.wav.prefix(4), encoding: .utf8), "RIFF")
        XCTAssertEqual(Array(draft.wav[20..<24]), [3, 0, 1, 0]) // Float32, mono.
        XCTAssertEqual(Array(draft.wav[24..<28]), [0x44, 0xac, 0, 0]) // 44,100 Hz little endian.
    }
    func testBadCapturesCannotBecomeBaseTones() throws {
        var samples = [Float](repeating: 0, count: 441_000)
        func analyze(_ lost: Bool = false) throws {
            _ = try CalibrationAnalyzer.analyze(samples: samples, guitarID: UUID(), route: RoutingPreset(),
                context: CaptureContext(path: .direct), lostFrames: lost, invalidSamples: false)
        }
        XCTAssertThrowsError(try analyze()) // Silence.
        samples = [Float](repeating: 0.25, count: 441_000)
        XCTAssertThrowsError(try analyze(true)) // Dropped frames.
        samples[0] = 1.2; XCTAssertThrowsError(try analyze()) // Clipping.
        samples[0] = .nan; XCTAssertThrowsError(try analyze()) // Nonfinite.
    }

    func testLegacyContextDoesNotInventSignalPath() throws {
        let data = Data("{\"guitarVolume\":\"10\",\"guitarTone\":\"10\",\"interfaceGainNote\":\"unchanged\"}".utf8)
        let context = try JSONDecoder().decode(CaptureContext.self, from: data)
        XCTAssertEqual(context.path, .unspecified)
        XCTAssertEqual(context.guitarVolume, "10")
        XCTAssertEqual(context.guitarTone, "10")
        XCTAssertEqual(context.interfaceGainNote, "unchanged")
        XCTAssertEqual(context.deviceNote, "")
    }
    func testKemperContextRoundTripsAndUnknownPathCannotBeCaptured() throws {
        var context = CaptureContext(path: .kemperBypass)
        context.deviceNote = "Kemper PROFILER Stage"; context.firmwareNote = "14.2.2.68644"
        context.outputNote = "User-entered bypass/output settings"
        XCTAssertEqual(try JSONDecoder().decode(CaptureContext.self, from: JSONEncoder().encode(context)), context)
        XCTAssertThrowsError(try CalibrationAnalyzer.analyze(samples: [Float](repeating: 0.25, count: 441_000),
            guitarID: UUID(), route: RoutingPreset(), context: CaptureContext(),
            lostFrames: false, invalidSamples: false)) { error in
            guard case CalibrationError.signalPathRequired = error else {
                return XCTFail("Expected missing-path error, got \(error)")
            }
        }
    }
    func testFreshGearFormDoesNotInheritAnotherPersonsGuitar() {
        let blank = GuitarIdentity()
        XCTAssertEqual(blank.manufacturer, "")
        XCTAssertEqual(blank.model, "")
        XCTAssertEqual(blank.pickupModel, "")
        XCTAssertFalse(blank.complete)
        XCTAssertEqual(blank.identificationStatus, "USER PROVIDED")
        XCTAssertTrue(GuitarIdentity.fenderTemplate().complete)
        XCTAssertEqual(GuitarIdentity.fenderTemplate().identificationStatus, "TEMPLATE — USER MUST CONFIRM")
    }
    func testIndependentLocalStoresDoNotShareGuitarsOrCalibrations() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = ProjectStore(url: root.appendingPathComponent("personA/project.json"))
        let second = ProjectStore(url: root.appendingPathComponent("personB/project.json"))
        var firstProject = Project()
        var config = GuitarConfiguration(id: UUID(), identity: GuitarIdentity.fenderTemplate())
        try config.save(record(), replacing: false)
        firstProject.gear = [config]; firstProject.selectedGuitarID = config.id
        try first.save(firstProject)
        XCTAssertTrue(try second.load().gear.isEmpty)
        var secondProject = Project(); secondProject.name = "Independent project"
        try second.save(secondProject)
        XCTAssertEqual(try first.load(), firstProject)
        XCTAssertEqual(try second.load(), secondProject)
    }
}
