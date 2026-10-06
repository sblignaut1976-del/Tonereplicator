import Foundation
import ToneCore

struct CalibrationDraft {
    let guitarID: UUID
    let record: SavedCalibration
    let wav: Data
}

enum CalibrationError: LocalizedError {
    case lostFrames, invalidSamples, clipped, quiet, analysisFailed
    var errorDescription: String? {
        switch self {
        case .lostFrames: return "Some audio frames were lost. Close busy applications and record again."
        case .invalidSamples: return "The input contains invalid samples. Check the interface and record again."
        case .clipped: return "The capture clipped. Lower the SSL input gain and record again."
        case .quiet: return "Not enough guitar signal was captured. Check the input and play throughout the recording."
        case .analysisFailed: return "The capture could not be analyzed at 44.1 kHz. Record again."
        }
    }
}

enum CalibrationAnalyzer {
    static func analyze(samples: [Float], guitarID: UUID, route: RoutingPreset,
                        context: CaptureContext, lostFrames: Bool, invalidSamples: Bool) throws -> CalibrationDraft {
        guard samples.count == 441_000 else { throw CalibrationError.analysisFailed }
        guard !lostFrames else { throw CalibrationError.lostFrames }
        guard !invalidSamples else { throw CalibrationError.invalidSamples }
        var measured = TRFingerprint()
        let success = samples.withUnsafeBufferPointer {
            tr_fingerprint($0.baseAddress, UInt32($0.count), 44_100, &measured)
        }
        guard success != 0 else { throw CalibrationError.analysisFailed }
        guard measured.invalid == 0 else { throw CalibrationError.invalidSamples }
        guard measured.clipped == 0 else { throw CalibrationError.clipped }
        guard measured.rms >= pow(10, -55.0 / 20),
              samples.filter({ abs($0) > 0.005 }).count >= samples.count / 20 else { throw CalibrationError.quiet }
        let bands = withUnsafeBytes(of: measured.band_db) { Array($0.bindMemory(to: Double.self)) }
        let fingerprint = CalibrationFingerprint(algorithm: "hann-fft2048-hop1024-log24-v1",
            sampleRate: 44_100, frames: samples.count, peak: measured.peak, rms: measured.rms,
            dc: measured.dc, bandDB: bands)
        let id = UUID()
        let record = SavedCalibration(id: id, createdAt: Date(), fingerprint: fingerprint,
            wavFilename: "\(id.uuidString).wav", interfaceUID: route.inputUID,
            inputChannel: route.inputChannel, context: context)
        return CalibrationDraft(guitarID: guitarID, record: record, wav: WaveFile.encode(samples))
    }
}

enum WaveFile {
    static func encode(_ samples: [Float]) -> Data {
        // RIFF WAVE, format 3 = IEEE Float32, mono, little-endian, canonical rate.
        var data = Data(); data.reserveCapacity(56 + samples.count * 4)
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(48 + samples.count * 4)); text("WAVE")
        text("fmt "); integer(UInt32(16)); integer(UInt16(3)); integer(UInt16(1))
        integer(UInt32(44_100)); integer(UInt32(44_100 * 4)); integer(UInt16(4)); integer(UInt16(32))
        text("fact"); integer(UInt32(4)); integer(UInt32(samples.count))
        text("data"); integer(UInt32(samples.count * 4))
        for sample in samples { integer(sample.bitPattern) }
        return data
    }
}

extension ProjectStore {
    func saveCapture(_ draft: CalibrationDraft) throws {
        let directory = url.deletingLastPathComponent().appendingPathComponent("Calibrations")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(draft.record.wavFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == draft.wav else { throw GearError.duplicateCapture }
            return // Retry after a failed project save may reuse the identical retained WAV.
        }
        try draft.wav.write(to: destination, options: .withoutOverwriting)
    }
}
