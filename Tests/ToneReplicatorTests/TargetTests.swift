import XCTest
import AVFoundation
@testable import ToneReplicator

final class TargetTests: XCTestCase {
    private func fixture(_ url: URL, rate: Double, channels: Int) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: UInt32(channels)))
        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(rate * 2)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let data = try XCTUnwrap(buffer.floatChannelData)
        for frame in 0..<Int(frames) {
            let sample = Float(0.25 * sin(2 * Double.pi * 1000 * Double(frame) / rate))
            data[0][frame] = sample
            if channels == 2 { data[1][frame] = -sample }
        }
        try file.write(from: buffer)
    }
    func test48kStereoImportPreservesOriginalAndProducesRepeatable44100Audio() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("reference.wav")
        try fixture(source, rate: 48_000, channels: 2)
        let bytes = try Data(contentsOf: source)
        let store = TargetStore(root: dir.appendingPathComponent("library"))
        let first = try ReferenceImporter.importAudio(url: source, start: 0.25, duration: 1, store: store)
        let second = try ReferenceImporter.importAudio(url: source, start: 0.25, duration: 1, store: store)
        XCTAssertEqual(first.originalSampleRate, 48_000)
        XCTAssertEqual(first.channels, 2)
        XCTAssertEqual(first.sourceFrames, 48_000)
        XCTAssertEqual(first.fingerprint.frames, 44_100)
        XCTAssertEqual(first.fingerprint.rms, 0.25 / sqrt(2), accuracy: 0.0005)
        XCTAssertEqual(first.analysisSHA256, second.analysisSHA256)
        XCTAssertEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let asset = store.assets.appendingPathComponent(first.id.uuidString)
        XCTAssertEqual(try Data(contentsOf: asset.appendingPathComponent(first.originalFilename)), bytes)
        XCTAssertEqual(first.originalSHA256, try ReferenceImporter.hashFile(source))
        let analysis = try AVAudioFile(forReading: asset.appendingPathComponent("analysis.wav"))
        XCTAssertEqual(analysis.processingFormat.sampleRate, 44_100)
        XCTAssertEqual(analysis.processingFormat.channelCount, 2)
        XCTAssertEqual(analysis.length, 44_100)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: analysis.processingFormat, frameCapacity: 4096))
        try analysis.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData)
        for i in 0..<Int(buffer.frameLength) { XCTAssertEqual(data[0][i], -data[1][i], accuracy: 0.000001) }
    }
    func testCanonicalMonoAndTargetDetailsSurviveStoreReload() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("mono.wav")
        try fixture(source, rate: 44_100, channels: 1)
        let store = TargetStore(root: dir.appendingPathComponent("library"))
        var reference = try ReferenceImporter.importAudio(url: source, start: 0, duration: 1, store: store)
        reference.artist = "Fixture artist"; reference.recordingVersion = "Test take"; reference.part = "Intro"
        var claim = TargetClaim(); claim.topic = "Guitar"; claim.claim = "Unknown"
        reference.claims = [claim]
        var library = TargetLibrary(); library.references = [reference]; library.selectedID = reference.id
        try store.save(library)
        XCTAssertEqual(try store.load(), library)
        XCTAssertEqual(reference.fingerprint.frames, 44_100)
        XCTAssertEqual(reference.fingerprint.rms, 0.25 / sqrt(2), accuracy: 0.00001)
        XCTAssertEqual(reference.claims[0].status, .unknown)
    }
    func testInvalidSectionRollsBackAssetsAndDoesNotModifySource() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("reference.wav")
        try fixture(source, rate: 48_000, channels: 1)
        let bytes = try Data(contentsOf: source)
        let store = TargetStore(root: dir.appendingPathComponent("library"))
        XCTAssertThrowsError(try ReferenceImporter.importAudio(url: source, start: 1.5, duration: 1, store: store))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.assets.path), [])
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertThrowsError(try ReferenceImporter.importAudio(url: source, start: -.infinity, duration: 1, store: store))
        XCTAssertThrowsError(try ReferenceImporter.importAudio(url: source, start: 0, duration: 31, store: store))
    }
    func testEvidenceRequiresSourcesAndRetainsIndividualStatuses() throws {
        for status in EvidenceStatus.allCases {
            var claim = TargetClaim(); claim.topic = "Amp"; claim.claim = "Example hypothesis"; claim.status = status
            if status != .unknown { XCTAssertThrowsError(try claim.validate()) }
            claim.source = "Fixture interview"; claim.sourceVersion = "Page 2"
            try claim.validate()
            let loaded = try JSONDecoder().decode(TargetClaim.self, from: JSONEncoder().encode(claim))
            XCTAssertEqual(loaded.status, status)
            XCTAssertEqual(loaded.sourceVersion, "Page 2")
            XCTAssertEqual(loaded.assessment, "User assessment")
        }
    }
    func testNewerLibraryAndInvalidSelectionArePreserved() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TargetStore(root: dir)
        let bytes = Data("{\"schemaVersion\":99,\"references\":[]}".utf8)
        try bytes.write(to: store.url)
        XCTAssertThrowsError(try store.save(TargetLibrary()))
        XCTAssertEqual(try Data(contentsOf: store.url), bytes)
        var library = TargetLibrary(); library.selectedID = UUID()
        XCTAssertThrowsError(try library.validate())
    }
}
