import SwiftUI

@main
struct ToneReplicatorApp: App {
    @StateObject private var audio = AudioSession()
    var body: some Scene {
        WindowGroup("Tone Replicator") {
            FoundationView(audio: audio)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
                .onDisappear { audio.stop() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in audio.stop() }
        }
    }
}

struct FoundationView: View {
    @ObservedObject var audio: AudioSession
    private let blue = Color(red: 0.25, green: 0.55, blue: 1)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 26) {
                Image(systemName: "waveform").font(.system(size: 30)).foregroundStyle(blue)
                Text("TONE\nREPLICATOR").font(.system(size: 19, weight: .bold, design: .rounded))
                Label("HOME", systemImage: "house.fill").foregroundStyle(blue)
                ForEach(["TARGET", "MY GUITAR", "MATCH", "RIG"], id: \.self) { title in
                    Text(title).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Foundation build\nM1 · Live validation pending")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(width: 205, alignment: .leading)
                .background(Color(red: 0.055, green: 0.065, blue: 0.085))
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("Your sound starts here.").font(.system(size: 34, weight: .semibold))
                    Text("Connect your guitar interface and check your live input.")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("AUDIO INTERFACE").font(.caption.weight(.bold)).foregroundStyle(blue)
                            Spacer()
                            Text("44.1 kHz").font(.caption.monospaced()).foregroundStyle(.green)
                        }
                        Picker("Input interface", selection: Binding(get: { audio.project.selectedInterfaceUID }, set: { audio.selectInput($0) })) {
                            Text("Choose an interface").tag("")
                            ForEach(audio.devices.filter { $0.inputs > 0 }) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }.disabled(audio.running || audio.starting)
                        Picker("Guitar input", selection: Binding(get: { audio.route.inputChannel }, set: { audio.route.inputChannel = $0 })) {
                            let count = audio.devices.first { $0.uid == audio.project.selectedInterfaceUID }?.inputs ?? 0
                            ForEach(0..<count, id: \.self) { channel in Text("Input \(channel + 1)").tag(channel) }
                        }.disabled(audio.running || audio.starting)
                        Picker("Output interface", selection: Binding(get: { audio.route.outputUID }, set: { audio.route.outputUID = $0 })) {
                            Text("Choose an interface").tag("")
                            ForEach(audio.devices.filter { $0.outputs > 0 }) { device in Text(device.name).tag(device.uid) }
                        }.disabled(audio.running || audio.starting)
                        Text("Use the same interface for input and output in this foundation build. Set it to 44,100 Hz in Audio MIDI Setup.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(audio.running ? "Stop audio" : "Start audio") {
                                if audio.running { audio.stop() } else { Task { await audio.start() } }
                            }.buttonStyle(.borderedProminent).tint(blue).disabled(audio.starting)
                            Button("Refresh interfaces") { audio.refresh() }.disabled(audio.running || audio.starting)
                        }
                    }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("LIVE INPUT").font(.caption.weight(.bold)).foregroundStyle(.red)
                            Spacer()
                            Text(audio.running ? "Listening" : "Stopped").font(.caption).foregroundStyle(.secondary)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.06))
                                Capsule().fill(audio.peak >= 1 ? Color.yellow : Color.red)
                                    .frame(width: max(0, geometry.size.width * CGFloat(min(1, audio.peak))))
                            }
                        }.frame(height: 12)
                        Text(audio.peak >= 1 ? "Clipping — lower the interface input gain." : audio.status)
                            .font(.callout).foregroundStyle(audio.peak >= 1 ? Color.yellow : Color.secondary)
                        Toggle("Listen through the app", isOn: Binding(get: { audio.monitoring }, set: { audio.setMonitoring($0) }))
                            .disabled(!audio.running)
                        Text("Use headphones and start with low output volume. Turn off the interface’s direct monitoring when comparing app monitoring.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Diagnostics") {
                            VStack(alignment: .leading) {
                                Text("Received frames: \(audio.frames)")
                                Text("Invalid samples: \(audio.invalid)")
                                Text(String(format: "Peak %.1f dBFS · RMS %.1f dBFS", 20 * log10(max(audio.peak, 0.000001)), 20 * log10(max(audio.rms, 0.000001))))
                                Text("Meters show measured input only. Matching and hardware latency have not been validated.")
                            }.font(.caption.monospaced()).padding(.top, 8)
                        }
                    }.padding(24).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    if let error = audio.error {
                        Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.yellow)
                    }
                    Text("Next: validate your interface on a Mac, then build your Guitar & Base Tone workflow.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(38)
            }.background(Color(red: 0.075, green: 0.085, blue: 0.105))
        }
    }
}
