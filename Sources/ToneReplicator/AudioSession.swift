import AVFoundation
import AudioToolbox
import Combine
import ToneCore

@MainActor
final class AudioSession: ObservableObject {
    @Published var devices: [AudioDevice] = []
    @Published var project = Project()
    @Published var running = false
    @Published var starting = false
    @Published var monitoring = false
    @Published var peak: Float = 0
    @Published var rms: Float = 0
    @Published var frames: UInt64 = 0
    @Published var invalid: UInt64 = 0
    @Published var status = "Choose your interface, then start audio."
    @Published var error: String?
    private var engine: AVAudioEngine?
    private var timer: AnyCancellable?
    private var meter: OpaquePointer?
    private var store: ProjectStore?
    private var projectLoadFailed = false
    private var tapInstalled = false

    init() {
        do { let store = try ProjectStore.standard(); self.store = store; project = try store.load() }
        catch { projectLoadFailed = true; self.error = "Project could not be loaded: \(error.localizedDescription)" }
        refresh()
    }

    var route: RoutingPreset {
        get { project.routingByInterface[project.selectedInterfaceUID] ?? RoutingPreset() }
        set {
            guard !running, !starting else { return }
            project.routingByInterface[project.selectedInterfaceUID] = newValue
            persist()
        }
    }
    func selectInput(_ uid: String) {
        guard !running, !starting else { return }
        project.selectedInterfaceUID = uid
        if project.routingByInterface[uid] == nil {
            let device = devices.first { $0.uid == uid }
            var preset = RoutingPreset(); preset.inputUID = uid
            if let device, device.outputs > 0 { preset.outputUID = uid }
            project.routingByInterface[uid] = preset
        }
        persist()
    }
    private func persist() {
        // Never replace an unreadable or newer project with an empty default.
        guard !projectLoadFailed, let store else { return }
        do { try store.save(project) }
        catch { self.error = "Settings were not saved: \(error.localizedDescription)" }
    }
    func refresh() {
        guard !running, !starting else { return }
        do { devices = try Devices.discover() }
        catch { self.error = error.localizedDescription }
    }
    func setMonitoring(_ enabled: Bool) {
        monitoring = enabled && running
        engine?.mainMixerNode.outputVolume = monitoring ? 1 : 0
    }
    func start() async {
        guard !running, !starting else { return }
        starting = true
        defer { starting = false }
        error = nil
        guard !projectLoadFailed else {
            error = "Resolve the saved-project error before starting. The original file has been preserved."
            return
        }
        let permission = await AVCaptureDevice.requestAccess(for: .audio)
        guard permission else {
            error = "Enable microphone access for Tone Replicator in System Settings → Privacy & Security → Microphone."
            return
        }
        do {
            // IDs may change after reconnecting, so resolve persisted UIDs again.
            devices = try Devices.discover()
            guard let input = devices.first(where: { $0.uid == route.inputUID }),
                  let output = devices.first(where: { $0.uid == route.outputUID }) else {
                throw AudioFailure.message("Selected interface is unavailable. Reconnect it and refresh.")
            }
            guard input.id == output.id else {
                throw AudioFailure.message("M1 requires one duplex interface for input and output. Separate-device clock alignment is not validated yet.")
            }
            guard tr_route_valid(route.inputChannel, input.inputs) != 0, output.outputs > 0 else {
                throw AudioFailure.message("Select an available guitar input and an interface with output channels.")
            }
            guard tr_rate_supported(try Devices.rate(input.id)) != 0 else {
                throw AudioFailure.message("Set this interface to 44,100 Hz in Audio MIDI Setup, then try again. The app does not change your hardware rate silently.")
            }
            guard let meter = tr_meter_create() else { throw AudioFailure.message("Audio telemetry could not be allocated.") }
            self.meter = meter
            let engine = AVAudioEngine(); self.engine = engine
            let inputNode = engine.inputNode; let outputNode = engine.outputNode
            guard let inputUnit = inputNode.audioUnit, let outputUnit = outputNode.audioUnit else {
                throw AudioFailure.message("CoreAudio input/output units are unavailable.")
            }
            var inputID = input.id; var outputID = output.id
            try Devices.checked(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &inputID, UInt32(MemoryLayout<AudioDeviceID>.size)), "Select input interface")
            try Devices.checked(AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &outputID, UInt32(MemoryLayout<AudioDeviceID>.size)), "Select output interface")
            let format = inputNode.outputFormat(forBus: 0)
            guard tr_rate_supported(format.sampleRate) != 0,
                  tr_rate_supported(outputNode.inputFormat(forBus: 0).sampleRate) != 0,
                  route.inputChannel < format.channelCount,
                  format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
                throw AudioFailure.message("The audio graph must expose noninterleaved Float32 input and 44.1 kHz input/output. Check Audio MIDI Setup.")
            }
            guard let mono = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1) else {
                throw AudioFailure.message("Could not create the canonical audio format.")
            }
            engine.connect(inputNode, to: engine.mainMixerNode, format: mono)
            // Set the map after negotiating the one-channel application format.
            // Route only the selected guitar channel, not all microphone/line inputs.
            var map = [Int32(route.inputChannel)]
            try map.withUnsafeMutableBytes { raw in
                try Devices.checked(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_ChannelMap,
                    kAudioUnitScope_Output, 1, raw.baseAddress!, UInt32(raw.count)), "Select guitar channel")
            }
            engine.mainMixerNode.outputVolume = 0
            inputNode.installTap(onBus: 0, bufferSize: 256, format: mono) { buffer, _ in
                guard let data = buffer.floatChannelData else { return }
                tr_meter_process(meter, data[0], buffer.frameLength)
            }
            tapInstalled = true
            engine.prepare(); try engine.start()
            running = true; monitoring = false
            status = "Live input • 44.1 kHz • \(input.name) • Input \(route.inputChannel + 1)"
            timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, let meter = self.meter else { return }
                self.peak = tr_meter_peak(meter); self.rms = tr_meter_rms(meter)
                self.frames = tr_meter_frames(meter); self.invalid = tr_meter_invalid(meter)
                if self.engine?.isRunning != true { self.stop(); self.error = "Audio stopped. Check the interface connection and restart audio." }
                else if (try? Devices.rate(input.id)) != 44_100 {
                    self.stop(); self.error = "Interface disconnected or sample rate changed. Restore 44.1 kHz and restart audio."
                }
            }
        } catch { stop(); self.error = error.localizedDescription }
    }
    func stop() {
        timer?.cancel(); timer = nil
        engine?.mainMixerNode.outputVolume = 0
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil
        if let meter { tr_meter_destroy(meter) }; meter = nil
        running = false; monitoring = false; peak = 0; rms = 0
        status = "Audio stopped. Routing settings are saved locally."
    }
}
