import Foundation
import ToneCore

struct CalibrationDraft {
    let guitarID: UUID
    let record: SavedCalibration
    let wav: Data
}

enum CalibrationError: LocalizedError {
    case lostFrames, invalidSamples, clipped, quiet, analysisFailed, signalPathRequired
    var errorDescription: String? {
        switch self {
        case .lostFrames: return "Some audio frames were lost. Close busy applications and record again."
        case .invalidSamples: return "The input contains invalid samples. Check the interface and record again."
        case .clipped: return "The capture clipped. Lower the interface input gain and record again."
        case .quiet: return "Not enough guitar signal was captured. Check the input and play throughout the recording."
        case .analysisFailed: return "The capture could not be analyzed at 44.1 kHz. Record again."
        case .signalPathRequired: return "Choose the actual guitar signal path before recording."
        }
    }
}

enum CalibrationAnalyzer {
    static func analyze(samples: [Float], guitarID: UUID, route: RoutingPreset,
                        context: CaptureContext, lostFrames: Bool, invalidSamples: Bool) throws -> CalibrationDraft {
        let channels = route.stereo ? 2 : 1
        guard samples.count == 441_000 * channels else { throw CalibrationError.analysisFailed }
        guard context.path != .unspecified else { throw CalibrationError.signalPathRequired }
        guard !lostFrames else { throw CalibrationError.lostFrames }
        guard !invalidSamples else { throw CalibrationError.invalidSamples }
        let left = channels == 1 ? samples : stride(from: 0, to: samples.count, by: 2).map { samples[$0] }
        let right = channels == 1 ? [] : stride(from: 1, to: samples.count, by: 2).map { samples[$0] }
        func measure(_ channel: [Float]) throws -> TRFingerprint {
            var result = TRFingerprint()
            let success = channel.withUnsafeBufferPointer {
                tr_fingerprint($0.baseAddress, UInt32($0.count), 44_100, &result)
            }
            guard success != 0 else { throw CalibrationError.analysisFailed }
            return result
        }
        let measured = try measure(left)
        let other: TRFingerprint
        if channels == 2 { other = try measure(right) } else { other = measured }
        guard measured.invalid == 0 && other.invalid == 0 else { throw CalibrationError.invalidSamples }
        guard measured.clipped == 0 && other.clipped == 0 else { throw CalibrationError.clipped }
        let rms = sqrt((measured.rms * measured.rms + other.rms * other.rms) / 2)
        guard rms >= pow(10, -55.0 / 20),
              samples.filter({ abs($0) > 0.005 }).count >= samples.count / 20 else { throw CalibrationError.quiet }
        let firstBands = withUnsafeBytes(of: measured.band_db) { Array($0.bindMemory(to: Double.self)) }
        let otherBands = withUnsafeBytes(of: other.band_db) { Array($0.bindMemory(to: Double.self)) }
        let bands = zip(firstBands, otherBands).map {
            10 * log10(max(1e-12, (pow(10, $0.0 / 10) + pow(10, $0.1 / 10)) / 2))
        }
        var correlation: Double? = nil
        if channels == 2 {
            var cross = 0.0, leftEnergy = 0.0, rightEnergy = 0.0
            for i in left.indices {
                let l = Double(left[i]) - measured.dc, r = Double(right[i]) - other.dc
                cross += l*r; leftEnergy += l*l; rightEnergy += r*r
            }
            if leftEnergy > 0 && rightEnergy > 0 { correlation = min(1, max(-1, cross / sqrt(leftEnergy*rightEnergy))) }
        }
        let fingerprint = CalibrationFingerprint(algorithm: channels == 1 ? "hann-fft2048-hop1024-log24-v1" : "hann-fft2048-hop1024-log24-stereo-energy-v1",
            sampleRate: 44_100, frames: samples.count / channels, peak: max(measured.peak, other.peak), rms: rms,
            dc: (measured.dc + other.dc) / 2, bandDB: bands, stereoCorrelation: correlation)
        let id = UUID()
        let record = SavedCalibration(id: id, createdAt: Date(), fingerprint: fingerprint,
            wavFilename: "\(id.uuidString).wav", interfaceUID: route.inputUID,
            inputChannel: route.inputChannel, context: context, channels: channels)
        return CalibrationDraft(guitarID: guitarID, record: record, wav: WaveFile.encode(samples, channels: channels))
    }
}

enum WaveFile {
    static func encode(_ samples: [Float], channels: Int = 1) -> Data {
        // RIFF WAVE, format 3 = IEEE Float32, interleaved, little-endian, canonical rate.
        var data = Data(); data.reserveCapacity(56 + samples.count * 4)
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        text("RIFF"); integer(UInt32(48 + samples.count * 4)); text("WAVE")
        text("fmt "); integer(UInt32(16)); integer(UInt16(3)); integer(UInt16(channels))
        integer(UInt32(44_100)); integer(UInt32(44_100 * 4 * channels)); integer(UInt16(4 * channels)); integer(UInt16(32))
        text("fact"); integer(UInt32(4)); integer(UInt32(samples.count / channels))
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
