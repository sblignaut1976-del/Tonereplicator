import SwiftUI

struct TargetView: View {
    @ObservedObject var target: TargetSession
    private let blue = Color(red: 0.25, green: 0.55, blue: 1)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Choose your target tone.").font(.system(size: 34, weight: .semibold))
                Text("Use a section where the guitar is clear. Other instruments and mix processing are included in the measurement.")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 14) {
                    Text("REFERENCE AUDIO").font(.caption.weight(.bold)).foregroundStyle(blue)
                    HStack {
                        TextField("Start (seconds)", text: $target.startText)
                        TextField("Length (1–30 seconds)", text: $target.durationText)
                    }
                    Text("Start (seconds) / Length (seconds). Default: start 0, length 10. These values apply to the next import.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Import audio…") { target.chooseAudio() }.buttonStyle(.borderedProminent).tint(blue)
                    if target.importing { ProgressView("Importing reference…") }
                    Text(target.message).font(.callout)
                }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                if !target.library.references.isEmpty {
                    Picker("Saved target", selection: Binding(get: { target.library.selectedID }, set: { target.select($0) })) {
                        ForEach(target.library.references) { reference in
                            Text("\(reference.title) · \(reference.importedAt.formatted(date: .abbreviated, time: .standard))")
                                .tag(Optional(reference.id))
                        }
                    }
                }
                if let reference = target.selected {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TARGET DETAILS").font(.caption.weight(.bold)).foregroundStyle(blue)
                        TextField("Title / song", text: $target.title)
                        TextField("Artist (optional)", text: $target.artist)
                        TextField("Recording / version (optional)", text: $target.recordingVersion)
                        TextField("Guitar part (optional)", text: $target.part)
                        Button("Save details") { target.saveDetails() }
                        Label("Measured reference · 44.1 kHz · \(reference.channels == 2 ? "Stereo" : "Mono")", systemImage: "waveform")
                            .foregroundStyle(.green)
                        Text(String(format: "Section: %.2f–%.2f seconds · RMS %.1f dBFS", reference.startSeconds,
                            reference.startSeconds + reference.duration, 20 * log10(max(1e-12, reference.fingerprint.rms))))
                        if reference.fingerprint.peak >= 1 {
                            Text("This section reaches digital full scale. Its level and distortion may affect comparison.").foregroundStyle(.yellow)
                        }
                        DisclosureGroup("Source and analysis details") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Original file: \(reference.sourceName)")
                                Text("Source sample rate: \(Int(reference.originalSampleRate)) Hz")
                                Text("Analysis frames: \(reference.fingerprint.frames)")
                                Text("Conversion: \(reference.conversion)")
                                Text("Original SHA-256: \(reference.originalSHA256)").textSelection(.enabled)
                                Text("Analysis SHA-256: \(reference.analysisSHA256)").textSelection(.enabled)
                                Button("Show preserved audio files") { target.revealFiles() }
                            }.font(.caption).padding(.top, 8)
                        }
                    }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 14) {
                        Text("SONG / GEAR EVIDENCE").font(.caption.weight(.bold)).foregroundStyle(blue)
                        Text("Add individual claims about the recording, guitar, pickups, pedals, amp, cabinet, microphones or mix. Labels reflect your source assessment; audio analysis does not verify historical gear.")
                            .font(.callout).foregroundStyle(.secondary)
                        ForEach(reference.claims) { claim in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(claim.topic): \(claim.claim)")
                                Text(claim.status.rawValue).font(.caption.weight(.bold))
                                    .foregroundStyle(claim.status == .verified ? Color.green : Color.yellow)
                                Text("\(claim.assessment) · \(claim.assessedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !claim.source.isEmpty { Text("Source: \(claim.source)").textSelection(.enabled) }
                                if !claim.sourceVersion.isEmpty { Text("Version / page: \(claim.sourceVersion)") }
                            }.padding(12).background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                        }
                        TextField("Topic (e.g. bridge pickup)", text: $target.claimDraft.topic)
                        TextField("Claim / unknown detail", text: $target.claimDraft.claim)
                        Picker("Evidence status", selection: $target.claimDraft.status) {
                            ForEach(EvidenceStatus.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        TextField("Source URL / document / interview", text: $target.claimDraft.source)
                        TextField("Version / page / timestamp (optional)", text: $target.claimDraft.sourceVersion)
                        Button("Add evidence claim") { target.addClaim() }
                    }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                }
                if let error = target.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.yellow) }
            }.padding(38).textFieldStyle(.roundedBorder).disabled(target.importing)
        }.background(Color(red: 0.075, green: 0.085, blue: 0.105))
    }
}
