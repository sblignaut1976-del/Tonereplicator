import AVFoundation

struct SpectralComparison {
    let percent: Double
    let errorDB: Double
    let levelDifferenceDB: Double

    static func relativeBands(_ fingerprint: CalibrationFingerprint) -> [Double] {
        let energy = fingerprint.bandDB.reduce(0.0) { $0 + pow(10, $1 / 10) }
        let totalDB = 10 * log10(max(1e-12, energy))
        return fingerprint.bandDB.map { max(-60, $0 - totalDB) }
    }
    static func compare(reference: CalibrationFingerprint?, live: CalibrationFingerprint?) -> SpectralComparison? {
        guard let reference, let live,
              reference.bandDB.count == 24, live.bandDB.count == 24,
              reference.bandDB.allSatisfy(\.isFinite), live.bandDB.allSatisfy(\.isFinite),
              reference.rms.isFinite, live.rms.isFinite,
              reference.rms >= 0.001, live.rms >= 0.001,
              reference.peak < 1, live.peak < 1 else { return nil }
        let a = relativeBands(reference), b = relativeBands(live)
        var squared = 0.0, weightSum = 0.0
        for index in a.indices {
            let weight = sqrt(max(pow(10, a[index] / 10), pow(10, b[index] / 10)))
            let delta = a[index] - b[index]
            squared += weight * delta * delta; weightSum += weight
        }
        let error = sqrt(squared / weightSum)
        return SpectralComparison(percent: 100 * exp(-error / 12), errorDB: error,
            levelDifferenceDB: 20 * log10(live.rms / reference.rms))
    }
}

struct ReferenceTimeline {
    static let windowFrames = 8192
    static let stepFrames = 4410
    let frameCount: Int
    let spectra: [CalibrationFingerprint?]
    let envelope: [Float]

    static func make(samples: [Float], channels: Int) throws -> ReferenceTimeline {
        guard channels == 1 || channels == 2, samples.count % channels == 0,
              samples.count / channels >= 2048, samples.count / channels <= 1_323_000,
              samples.allSatisfy(\.isFinite) else { throw TargetError.invalidAudio }
        let frameCount = samples.count / channels
        var spectra: [CalibrationFingerprint?] = []
        for frame in stride(from: 0, to: frameCount, by: stepFrames) {
            let first = min(frame, max(0, frameCount - windowFrames))
            let end = min(frameCount, first + windowFrames)
            let section = Array(samples[(first * channels)..<(end * channels)])
            spectra.append(try? ReferenceImporter.analyze(section, channels: channels))
        }
        var envelope: [Float] = []
        let binFrames = max(1, (frameCount + 239) / 240)
        for frame in stride(from: 0, to: frameCount, by: binFrames) {
            let end = min(frameCount, frame + binFrames)
            var peak: Float = 0
            for index in (frame * channels)..<(end * channels) { peak = max(peak, abs(samples[index])) }
            envelope.append(peak)
        }
        return ReferenceTimeline(frameCount: frameCount, spectra: spectra, envelope: envelope)
    }
    func spectrum(at frame: Int) -> CalibrationFingerprint? {
        guard frame >= 0, frame < frameCount else { return nil }
        return spectra[min(spectra.count - 1, frame / Self.stepFrames)]
    }
}

struct PreparedReference {
    let id: UUID
    let buffer: AVAudioPCMBuffer
    let timeline: ReferenceTimeline
    static func load(_ reference: TargetReference, url: URL) throws -> PreparedReference {
        guard try ReferenceImporter.hashFile(url) == reference.analysisSHA256 else {
            throw AudioFailure.message("The analysis audio has changed. Import the reference again; the original is preserved.")
        }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.processingFormat.sampleRate == 44_100,
              Int(file.processingFormat.channelCount) == reference.channels,
              file.length == Int64(reference.fingerprint.frames),
              file.length >= 2048, file.length <= 1_323_000,
              let source = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)),
              let stereo = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let playback = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: UInt32(file.length)) else {
            throw TargetError.invalidAudio
        }
        try file.read(into: source)
        guard source.frameLength == UInt32(file.length), let input = source.floatChannelData,
              let output = playback.floatChannelData else { throw TargetError.invalidAudio }
        playback.frameLength = source.frameLength
        var samples: [Float] = []; samples.reserveCapacity(Int(file.length) * reference.channels)
        for frame in 0..<Int(source.frameLength) {
            for channel in 0..<reference.channels { samples.append(input[channel][frame]) }
            output[0][frame] = input[0][frame]
            output[1][frame] = input[reference.channels - 1][frame]
        }
        return PreparedReference(id: reference.id, buffer: playback,
            timeline: try ReferenceTimeline.make(samples: samples, channels: reference.channels))
    }
}
