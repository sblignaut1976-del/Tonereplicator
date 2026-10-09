import SwiftUI

struct MatchView: View {
    @ObservedObject var audio: AudioSession
    @ObservedObject var target: TargetSession
    private let blue = Color(red: 0.25, green: 0.55, blue: 1)
    private var comparison: SpectralComparison? {
        guard audio.referencePlaying else { return nil }
        return SpectralComparison.compare(reference: audio.referenceSpectrum, live: audio.liveSpectrum)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Hear it. Play it. Compare.").font(.system(size: 32, weight: .semibold))
                if let reference = target.selected {
                    controls(reference)
                    spectrum
                    listening
                } else {
                    Text("Import a reference on TARGET first.").foregroundStyle(.secondary)
                    Button("Choose target") { audio.screen = .target }.buttonStyle(.borderedProminent).tint(blue)
                }
                if let error = audio.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.yellow) }
            }.padding(38)
        }.background(Color(red: 0.075, green: 0.085, blue: 0.105))
            .onDisappear { audio.stopReference() }
    }
    private func controls(_ reference: TargetReference) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(reference.title).font(.title3.weight(.semibold))
            Text(reference.artist.isEmpty ? "Artist unknown" : reference.artist).foregroundStyle(.secondary)
            if let guitar = audio.selectedGuitar {
                Text("My guitar: \(guitar.identity.title)").font(.caption)
            }
            if !audio.running {
                Text("Start audio on HOME using your incoming guitar channels and listening outputs.").foregroundStyle(.yellow)
                Button("Audio setup") { audio.screen = .home }
            }
            HStack {
                Button("Load selected reference") {
                    if let url = target.selectedAnalysisURL { audio.prepareReference(reference, url: url) }
                }.disabled(audio.referenceLoading || audio.captureBusy || audio.calibrationDraft != nil)
                Button(audio.referencePlaying ? "Stop reference" : "Play reference") {
                    if audio.referencePlaying { audio.stopReference() } else { audio.playReference() }
                }.buttonStyle(.borderedProminent).tint(blue)
                    .disabled(!audio.running || audio.loadedReferenceID != reference.id || audio.referenceLoading || audio.captureBusy || audio.calibrationDraft != nil)
            }
            if audio.referenceLoading { ProgressView("Preparing reference…") }
            if audio.loadedReferenceID == reference.id {
                ReferenceWaveform(envelope: audio.referenceEnvelope, position: audio.referencePosition, duration: audio.referenceDuration)
                    .frame(height: 64)
                Text(String(format: "%.1f / %.1f seconds · reference loops", audio.referencePosition, audio.referenceDuration))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }
    private var spectrum: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Reference", systemImage: "waveform").foregroundStyle(.green)
                Label("Live guitar", systemImage: "waveform").foregroundStyle(.red)
                Spacer()
            }.font(.caption.weight(.bold))
            SpectrumPlot(reference: audio.referenceSpectrum, live: audio.liveSpectrum).frame(height: 270)
            HStack {
                if let comparison {
                    Text(String(format: "Spectral similarity %.0f%%", comparison.percent)).font(.title3.weight(.semibold))
                    Spacer()
                    Text(String(format: "Shape difference %.1f dB", comparison.errorDB)).foregroundStyle(.yellow)
                } else {
                    Text("Play the reference and your guitar to compare. Silence or clipping pauses the score.")
                        .foregroundStyle(.secondary)
                }
            }
            Text("Curves compare spectrum shape, with level differences removed. This is not a complete tone-match score.")
                .font(.caption).foregroundStyle(.secondary)
            DisclosureGroup("Why / analysis details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Measured 24-band energy · Hann FFT 2048 / hop 1024 · 8192-frame windows · 44.1 kHz")
                    Text("Live windows cover about 186 ms, refreshed at up to 10 Hz. Hardware latency is not compensated yet.")
                    Text("Reference windows start at the playback position; live windows cover recently received input. Play the same phrase; this stage does not align performances automatically.")
                    Text("Shape score = 100 × exp(−weighted RMS band difference / 12 dB). Stereo uses channel energy, so opposite polarity does not cancel.")
                    if let comparison { Text(String(format: "Live minus reference level: %+.1f dB", comparison.levelDifferenceDB)) }
                    Text("Analyzer dropped samples: \(audio.spectrumDroppedSamples)")
                    Text("Selected calibration is retained. Calibration-driven recipe calculation, historical confidence and optimization are not implemented in this stage.")
                }.font(.caption).padding(.top, 8)
            }
        }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }
    private var listening: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LISTEN / A–B").font(.caption.weight(.bold)).foregroundStyle(blue)
            Picker("Listen to", selection: Binding(get: { audio.listening }, set: { audio.setListening($0) })) {
                ForEach(AudioSession.Listening.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(!audio.running)
            HStack {
                Text("Reference volume")
                Slider(value: Binding(get: { audio.referenceVolume }, set: { audio.setReferenceVolume($0) }), in: 0...1)
            }
            Text("Use headphones or low speaker volume. For A–B, turn off interface direct monitoring (SSL MIX toward USB). Guitar monitoring starts off; Guitar/Both enables it at −6 dB playback gain. Reference starts at 25% volume.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct SpectrumPlot: View {
    let reference: CalibrationFingerprint?
    let live: CalibrationFingerprint?
    var body: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                for row in 0...3 {
                    let y = size.height * CGFloat(row) / 3
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(line, with: .color(.white.opacity(0.08)), lineWidth: 1)
                }
                for (fingerprint, color) in [(reference, Color.green), (live, Color.red)] {
                    guard let fingerprint, fingerprint.bandDB.count == 24 else { continue }
                    let bands = SpectralComparison.relativeBands(fingerprint)
                    var path = Path()
                    for index in bands.indices {
                        let x = size.width * (CGFloat(index) + 0.5) / 24
                        let y = size.height * CGFloat(min(60, max(0, -bands[index]))) / 60
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path, with: .color(color), lineWidth: 2)
                }
            }.background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            HStack { Text("40 Hz"); Spacer(); Text("~900 Hz"); Spacer(); Text("20 kHz") }
                .font(.caption.monospaced()).foregroundStyle(.secondary)
            Text("Relative band energy · 0 to −60 dB · logarithmic frequency")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ReferenceWaveform: View {
    let envelope: [Float]
    let position: Double
    let duration: Double
    var body: some View {
        Canvas { context, size in
            guard !envelope.isEmpty else { return }
            var peaks = Path()
            for index in envelope.indices {
                let x = size.width * (CGFloat(index) + 0.5) / CGFloat(envelope.count)
                let height = size.height * CGFloat(min(1, envelope[index])) / 2
                peaks.move(to: CGPoint(x: x, y: size.height / 2 - height))
                peaks.addLine(to: CGPoint(x: x, y: size.height / 2 + height))
            }
            context.stroke(peaks, with: .color(.green.opacity(0.7)), lineWidth: 2)
            let x = size.width * CGFloat(duration > 0 ? min(1, max(0, position / duration)) : 0)
            var cursor = Path(); cursor.move(to: CGPoint(x: x, y: 0)); cursor.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(cursor, with: .color(.white), lineWidth: 1)
        }.background(.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }
}
