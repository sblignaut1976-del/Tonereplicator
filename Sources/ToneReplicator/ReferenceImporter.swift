import AVFoundation
import CryptoKit
import ToneCore

enum ReferenceImporter {
    static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func importAudio(url: URL, start: Double, duration: Double, store: TargetStore) throws -> TargetReference {
        guard start.isFinite, start >= 0, duration.isFinite, (1...30).contains(duration) else { throw TargetError.invalidClip }
        let id = UUID()
        let directory = store.assets.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { throw TargetError.unsupportedAudio }
        let original = directory.appendingPathComponent("original.\(ext)")
        try FileManager.default.copyItem(at: url, to: original)
        let originalHash = try hashFile(original)
        let file = try AVAudioFile(forReading: original, commonFormat: .pcmFormatFloat32, interleaved: false)
        let inputFormat = file.processingFormat
        let rate = inputFormat.sampleRate, channels = Int(inputFormat.channelCount)
        guard rate.isFinite, (8_000...192_000).contains(rate), channels == 1 || channels == 2 else { throw TargetError.unsupportedAudio }
        // Source-frame selection is rounded; output length is floored and trimmed.
        let startFrameValue = (start * rate).rounded()
        let selectedFrameValue = (duration * rate).rounded()
        guard startFrameValue < Double(file.length), selectedFrameValue <= Double(file.length) - startFrameValue else { throw TargetError.invalidClip }
        let firstFrame = Int64(startFrameValue), sourceFrames = Int64(selectedFrameValue)
        file.framePosition = firstFrame
        let expectedFrames = Int(floor(Double(sourceFrames) * 44_100 / rate))
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: UInt32(channels)),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 4096),
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4096) else { throw TargetError.conversionFailed }
        converter.primeMethod = .none
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        var remaining = sourceFrames
        var readError: Error?
        var samples: [Float] = []; samples.reserveCapacity(expectedFrames * channels)
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { requested, inputStatus in
                guard remaining > 0, readError == nil else { inputStatus.pointee = .endOfStream; return nil }
                let count = AVAudioFrameCount(min(Int64(min(requested, input.frameCapacity)), remaining))
                do {
                    try file.read(into: input, frameCount: count)
                    guard input.frameLength > 0 else { throw TargetError.conversionFailed }
                    remaining -= Int64(input.frameLength)
                    inputStatus.pointee = .haveData
                    return input
                } catch {
                    readError = error; inputStatus.pointee = .endOfStream; return nil
                }
            }
            if let readError { throw readError }
            if let error { throw error }
            guard status != .error, let data = output.floatChannelData else { throw TargetError.conversionFailed }
            for frame in 0..<Int(output.frameLength) {
                if samples.count >= expectedFrames * channels { break }
                for channel in 0..<channels { samples.append(data[channel][frame]) }
            }
            if status == .endOfStream || samples.count == expectedFrames * channels { break }
            guard output.frameLength > 0 else { throw TargetError.conversionFailed }
        }
        guard samples.count == expectedFrames * channels else { throw TargetError.conversionFailed }
        let fingerprint = try analyze(samples, channels: channels)
        let analysis = directory.appendingPathComponent("analysis.wav")
        try WaveFile.encode(samples, channels: channels).write(to: analysis, options: .withoutOverwriting)
        let record = TargetReference(id: id, importedAt: Date(), title: url.deletingPathExtension().lastPathComponent,
            originalFilename: original.lastPathComponent, sourceName: url.lastPathComponent, originalSHA256: originalHash,
            originalSampleRate: rate, channels: channels, startSeconds: Double(firstFrame) / rate,
            sourceFrames: sourceFrames,
            conversion: "AVAudioConverter Float32 / max quality / no priming / source rounded / output floored-trimmed / v1 / \(ProcessInfo.processInfo.operatingSystemVersionString)",
            analysisSHA256: try hashFile(analysis), fingerprint: fingerprint)
        try record.validate()
        completed = true
        return record
    }

    static func analyze(_ samples: [Float], channels: Int) throws -> CalibrationFingerprint {
        var measurements: [TRFingerprint] = []
        for channel in 0..<channels {
            let values = stride(from: channel, to: samples.count, by: channels).map { samples[$0] }
            var measured = TRFingerprint()
            let result = values.withUnsafeBufferPointer { tr_fingerprint($0.baseAddress, UInt32($0.count), 44_100, &measured) }
            guard result != 0, measured.invalid == 0 else { throw TargetError.invalidAudio }
            measurements.append(measured)
        }
        let left = measurements[0], right = measurements[channels - 1]
        let rms = sqrt((left.rms * left.rms + right.rms * right.rms) / 2)
        guard rms > 1e-8 else { throw TargetError.invalidAudio }
        let lb = withUnsafeBytes(of: left.band_db) { Array($0.bindMemory(to: Double.self)) }
        let rb = withUnsafeBytes(of: right.band_db) { Array($0.bindMemory(to: Double.self)) }
        var bands: [Double] = []
        for i in lb.indices {
            let energy = (pow(10, lb[i] / 10) + pow(10, rb[i] / 10)) / 2
            bands.append(10 * log10(max(1e-12, energy)))
        }
        return CalibrationFingerprint(algorithm: "hann-fft2048-hop1024-log24-reference-energy-v1",
            sampleRate: 44_100, frames: samples.count / channels, peak: max(left.peak, right.peak),
            rms: rms, dc: (left.dc + right.dc) / 2, bandDB: bands)
    }
}
