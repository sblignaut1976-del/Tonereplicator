import XCTest
import AVFoundation
@testable import ToneReplicator

final class MatchTests: XCTestCase {
    private func tone(_ frequency: Double, gain: Double = 0.25, frames: Int = 8192) -> [Float] {
        (0..<frames).map { Float(gain * sin(2 * Double.pi * frequency * Double($0) / 44_100)) }
    }
    func testShapeComparisonIgnoresLevelButDetectsFrequencyDifference() throws {
        let reference = try ReferenceImporter.analyze(tone(1000), channels: 1)
        let quiet = try ReferenceImporter.analyze(tone(1000, gain: 0.025), channels: 1)
        let different = try ReferenceImporter.analyze(tone(4000), channels: 1)
        let same = try XCTUnwrap(SpectralComparison.compare(reference: reference, live: quiet))
        XCTAssertEqual(same.percent, 100, accuracy: 0.001)
        XCTAssertEqual(same.levelDifferenceDB, -20, accuracy: 0.001)
        let changed = try XCTUnwrap(SpectralComparison.compare(reference: reference, live: different))
        XCTAssertLessThan(changed.percent, 50)
        XCTAssertGreaterThan(changed.errorDB, 10)
    }
    func testScoreUnavailableForSilenceClippingMissingOrInvalidBands() throws {
        let reference = try ReferenceImporter.analyze(tone(1000), channels: 1)
        let silent = CalibrationFingerprint(algorithm: "fixture", sampleRate: 44_100, frames: 8192,
            peak: 0, rms: 0, dc: 0, bandDB: reference.bandDB)
        let clipped = CalibrationFingerprint(algorithm: "fixture", sampleRate: 44_100, frames: 8192,
            peak: 1, rms: 0.2, dc: 0, bandDB: reference.bandDB)
        let invalid = CalibrationFingerprint(algorithm: "fixture", sampleRate: 44_100, frames: 8192,
            peak: 0.5, rms: 0.2, dc: 0, bandDB: [.nan])
        XCTAssertNil(SpectralComparison.compare(reference: reference, live: silent))
        XCTAssertNil(SpectralComparison.compare(reference: reference, live: clipped))
        XCTAssertNil(SpectralComparison.compare(reference: reference, live: invalid))
        XCTAssertNil(SpectralComparison.compare(reference: nil, live: reference))
    }
    func testReferenceTimelineFollowsChangingAudioAndRetainsPolarityEnergy() throws {
        let mono = tone(1000, frames: 8820) + tone(4000, frames: 8820)
        var stereo: [Float] = []
        for value in mono { stereo.append(value); stereo.append(-value) }
        let timeline = try ReferenceTimeline.make(samples: stereo, channels: 2)
        XCTAssertEqual(timeline.frameCount, 17640)
        XCTAssertEqual(timeline.spectra.count, 4)
        XCTAssertLessThanOrEqual(timeline.envelope.count, 240)
        XCTAssertGreaterThan(try XCTUnwrap(timeline.envelope.max()), 0.24)
        let first = try XCTUnwrap(timeline.spectrum(at: 0))
        let later = try XCTUnwrap(timeline.spectrum(at: 8820))
        XCTAssertEqual(first.rms, 0.25 / sqrt(2), accuracy: 0.001)
        XCTAssertLessThan(try XCTUnwrap(SpectralComparison.compare(reference: first, live: later)).percent, 50)
        XCTAssertNil(timeline.spectrum(at: -1))
        XCTAssertNil(timeline.spectrum(at: 17640))
        let silent = try ReferenceTimeline.make(samples: [Float](repeating: 0, count: 8192), channels: 1)
        XCTAssertNil(silent.spectrum(at: 0))
        XCTAssertThrowsError(try ReferenceTimeline.make(samples: [.nan, 0], channels: 2))
    }
    func testPreparedReferenceValidatesHashAndDuplicatesMonoForStereoListening() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("source.wav")
        try WaveFile.encode(tone(1000, frames: 44_100)).write(to: source)
        let store = TargetStore(root: dir.appendingPathComponent("library"))
        let record = try ReferenceImporter.importAudio(url: source, start: 0, duration: 1, store: store)
        let analysis = store.assets.appendingPathComponent(record.id.uuidString).appendingPathComponent("analysis.wav")
        let prepared = try PreparedReference.load(record, url: analysis)
        XCTAssertEqual(prepared.id, record.id)
        XCTAssertEqual(prepared.buffer.format.channelCount, 2)
        XCTAssertEqual(prepared.buffer.frameLength, 44_100)
        XCTAssertEqual(prepared.timeline.frameCount, 44_100)
        let channels = try XCTUnwrap(prepared.buffer.floatChannelData)
        for i in 0..<Int(prepared.buffer.frameLength) { XCTAssertEqual(channels[0][i], channels[1][i]) }
        let original = try Data(contentsOf: analysis)
        var corrupted = original; corrupted[corrupted.count - 1] ^= 1
        try corrupted.write(to: analysis)
        XCTAssertThrowsError(try PreparedReference.load(record, url: analysis))
    }
}
