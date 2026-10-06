import SwiftUI

struct GuitarView: View {
    @ObservedObject var audio: AudioSession
    private let blue = Color(red: 0.25, green: 0.55, blue: 1)
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("My guitar. My Base Tone.").font(.system(size: 32, weight: .semibold))
                Text("Keep a separate source for each guitar, pickup position and switching mode.")
                    .foregroundStyle(.secondary)
                HStack {
                    Picker("Gear Vault", selection: Binding(get: { audio.project.selectedGuitarID }, set: { audio.selectGuitar($0) })) {
                        Text("Choose a saved configuration").tag(nil as UUID?)
                        ForEach(audio.project.gear) { config in Text(config.identity.title).tag(Optional(config.id)) }
                    }
                    Button(audio.showAddGuitar ? "Cancel" : "Add configuration") {
                        audio.showAddGuitar.toggle()
                    }
                }.disabled(audio.captureBusy || audio.calibrationDraft != nil)

                if audio.showAddGuitar || audio.project.gear.isEmpty {
                    addConfiguration
                }
                if let config = audio.selectedGuitar {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(config.identity.title).font(.title3.weight(.semibold))
                        Text("Pickup: \(config.identity.pickupModel.isEmpty ? "UNKNOWN" : config.identity.pickupModel)")
                        Text("Position/mode: \(config.identity.pickupPosition) · \(config.identity.switchingMode.isEmpty ? "UNKNOWN" : config.identity.switchingMode)")
                            .foregroundStyle(.secondary)
                        Picker("Base Tone source", selection: Binding(get: { config.activeSource }, set: { audio.selectSource($0) })) {
                            ForEach(BaseToneSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.pickerStyle(.segmented).disabled(audio.captureBusy || audio.calibrationDraft != nil)
                        if config.activeSource == .factory {
                            Text("UNKNOWN — no verified factory audio baseline is available for this exact configuration.")
                                .foregroundStyle(.yellow)
                            Text("Pickup names and web descriptions are identification evidence, not a measured Base Tone.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else if let saved = config.baseTone {
                            Label("Saved Base Tone", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Text(saved.createdAt, style: .date)
                            fingerprintDetails(saved.fingerprint)
                        } else {
                            Text("No calibration saved yet.").foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Identity and sources") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Identity status: \(config.identity.identificationStatus)")
                                Text("Variant: \(config.identity.variant.isEmpty ? "UNKNOWN" : config.identity.variant)")
                                Text("Year: \(config.identity.year.isEmpty ? "UNKNOWN" : config.identity.year)")
                                if let url = URL(string: config.identity.sourceURL), url.scheme == "https" {
                                    Link("User-supplied source", destination: url)
                                }
                                Text("Pickup resistance, magnet, inductance and output: UNKNOWN until verified.")
                                Text("Retained calibrations: \(config.calibrations.count)")
                                if let saved = config.baseTone {
                                    Text("Capture ID: \(saved.id.uuidString)").textSelection(.enabled)
                                    Text("Guitar volume: \(saved.context.guitarVolume.isEmpty ? "UNKNOWN" : saved.context.guitarVolume)")
                                    Text("Guitar tone: \(saved.context.guitarTone.isEmpty ? "UNKNOWN" : saved.context.guitarTone)")
                                    Text("Interface gain note: \(saved.context.interfaceGainNote.isEmpty ? "UNKNOWN" : saved.context.interfaceGainNote)")
                                }
                            }.font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 16) {
                        Text("RECORD MY CALIBRATION").font(.caption.weight(.bold)).foregroundStyle(blue)
                        Text("Use the guitar directly into the SSL instrument input. Keep the pickup, guitar controls and interface gain unchanged while recording.")
                            .font(.callout).foregroundStyle(.secondary)
                        TextField("Guitar volume setting (optional)", text: $audio.captureContext.guitarVolume)
                            .disabled(audio.captureBusy || audio.calibrationDraft != nil)
                        TextField("Guitar tone setting (optional)", text: $audio.captureContext.guitarTone)
                            .disabled(audio.captureBusy || audio.calibrationDraft != nil)
                        TextField("Interface gain note (optional)", text: $audio.captureContext.interfaceGainNote)
                            .disabled(audio.captureBusy || audio.calibrationDraft != nil)
                        Text("Play single notes across the strings and a few chords throughout the 10-second recording. Lower gain if the input clips.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !audio.running {
                            Text("Start audio on HOME first.").foregroundStyle(.yellow)
                            Button("Go to audio setup") { audio.screen = .home }
                        }
                        if audio.captureStage == .recording {
                            ProgressView(value: audio.captureProgress)
                            Text("\(Int(audio.captureProgress * 10)) / 10 seconds captured").font(.caption.monospaced())
                        } else if audio.captureStage == .analyzing {
                            ProgressView("Analyzing locally…")
                        }
                        Text(audio.calibrationMessage).font(.callout)
                        if let draft = audio.calibrationDraft {
                            fingerprintDetails(draft.record.fingerprint)
                            HStack {
                                Button(config.baseTone == nil ? "Save Base Tone" : "Replace Base Tone…") {
                                    if config.baseTone == nil { audio.saveCalibration(replacing: false) }
                                    else { audio.confirmReplacement = true }
                                }.buttonStyle(.borderedProminent).tint(blue)
                                Button("Discard recording") { audio.discardCapture() }
                            }
                        } else {
                            HStack {
                                Button(config.baseTone == nil ? "Record 10 seconds" : "Record new candidate") { audio.recordCalibration() }
                                    .buttonStyle(.borderedProminent).tint(blue)
                                    .disabled(!audio.running || audio.captureBusy)
                                if audio.captureBusy { Button("Cancel recording") { audio.discardCapture() } }
                            }
                        }
                        Text("Recording a candidate does not replace a saved Base Tone. Replacement retains the previous capture.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.textFieldStyle(.roundedBorder).padding(24)
                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                }
                if let error = audio.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.yellow) }
            }.padding(38)
        }.background(Color(red: 0.075, green: 0.085, blue: 0.105))
            .confirmationDialog("Replace the saved Base Tone for this exact configuration?", isPresented: $audio.confirmReplacement, titleVisibility: .visible) {
                Button("Replace Base Tone", role: .destructive) { audio.saveCalibration(replacing: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("The new recording becomes active. The previous calibration remains in your local history.") }
    }

    private var addConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add exact guitar / pickup configuration").font(.headline)
            HStack {
                Button("Use my Fender details") { audio.guitarDraft = GuitarIdentity() }
                Button("Use my Ibanez details") { audio.suggestIbanez() }
            }
            TextField("Manufacturer", text: $audio.guitarDraft.manufacturer)
            TextField("Family (optional)", text: $audio.guitarDraft.family)
            TextField("Model", text: $audio.guitarDraft.model)
            TextField("Variant (optional)", text: $audio.guitarDraft.variant)
            TextField("Year / revision (optional)", text: $audio.guitarDraft.year)
            TextField("Pickup model (optional)", text: $audio.guitarDraft.pickupModel)
            TextField("Pickup position", text: $audio.guitarDraft.pickupPosition)
            TextField("Switching / coil mode (optional)", text: $audio.guitarDraft.switchingMode)
            TextField("Source URL (optional)", text: $audio.guitarDraft.sourceURL)
            Text("Check these user-supplied details. Blank optional fields stay UNKNOWN. Adding another pickup position creates a separate configuration.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Save configuration") { audio.addGuitar() }.buttonStyle(.borderedProminent).tint(blue)
        }.textFieldStyle(.roundedBorder).padding(24)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .disabled(audio.captureBusy || audio.calibrationDraft != nil)
    }

    private func fingerprintDetails(_ fingerprint: CalibrationFingerprint) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("MEASURED · 44.1 kHz · \(Double(fingerprint.frames) / 44_100, specifier: "%.1f") seconds")
                .font(.caption.weight(.semibold)).foregroundStyle(.green)
            DisclosureGroup("Measured details") {
                Text(String(format: "Peak %.1f dBFS · RMS %.1f dBFS", 20 * log10(max(fingerprint.peak, 0.000001)), 20 * log10(max(fingerprint.rms, 0.000001))))
                Text("24 spectral power bands · \(fingerprint.algorithm)")
                Text("This is your captured guitar behavior, not a pickup specification or a tone-match score.")
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
