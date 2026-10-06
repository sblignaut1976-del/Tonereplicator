import AVFoundation
import AudioToolbox
import Combine
import ToneCore

@MainActor
final class AudioSession: ObservableObject {
    enum Screen { case home, target, guitar }
    enum CaptureStage { case idle, recording, analyzing, ready }
    @Published var screen = Screen.home
    @Published var guitarDraft = GuitarIdentity()
    @Published var captureContext = CaptureContext()
    @Published var showAddGuitar = false
    @Published var confirmReplacement = false
    @Published var captureStage = CaptureStage.idle
    @Published var captureProgress = 0.0
    @Published var calibrationMessage = "Record your guitar to create a measured Base Tone."
    @Published private(set) var calibrationDraft: CalibrationDraft?
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
    private var queue: OpaquePointer?
    private var scratch = [Float](repeating: 0, count: 65_536)
    private var captureSamples: [Float] = []
    private var captureGuitarID: UUID?
    private var captureRoute = RoutingPreset()
    private var recordedContext = CaptureContext()
    private var captureDropBaseline: UInt64 = 0
    private var captureToken = UUID()

    var captureBusy: Bool { captureStage == .recording || captureStage == .analyzing }
    var selectedGuitar: GuitarConfiguration? { project.gear.first { $0.id == project.selectedGuitarID } }
    func setStereoInput(_ enabled: Bool) {
        guard !running, !starting else { return }
        var next = route; next.stereo = enabled
        if enabled { next.inputChannel = (next.inputChannel / 2) * 2 }
        route = next
    }

    private func commit(_ candidate: Project) throws {
        guard !projectLoadFailed, let store else { throw AudioFailure.message("Saved project is unavailable. The original was preserved.") }
        try store.save(candidate)
        project = candidate
    }
    func addGuitar() {
        guard !captureBusy, calibrationDraft == nil else { return }
        do {
            guard guitarDraft.complete else { throw GearError.incompleteIdentity }
            var next = project
            if let existing = next.gear.first(where: { $0.identity == guitarDraft }) {
                next.selectedGuitarID = existing.id
            } else {
                let config = GuitarConfiguration(id: UUID(), identity: guitarDraft)
                next.gear.append(config); next.selectedGuitarID = config.id
            }
            try commit(next); showAddGuitar = false; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func suggestIbanez() {
        var identity = GuitarIdentity()
        identity.manufacturer = "Ibanez"; identity.family = "AZ"; identity.model = "AZ224F"
        identity.pickupModel = "Seymour Duncan Hyperion"; identity.pickupPosition = ""
        identity.switchingMode = ""; identity.sourceURL = ""
        identity.identificationStatus = "TEMPLATE — USER MUST CONFIRM"
        guitarDraft = identity
    }
    func selectGuitar(_ id: UUID?) {
        guard !captureBusy, calibrationDraft == nil else { return }
        do {
            guard id == nil || project.gear.contains(where: { $0.id == id }) else { throw GearError.missingConfiguration }
            var next = project; next.selectedGuitarID = id; try commit(next)
        } catch { self.error = error.localizedDescription }
    }
    func selectSource(_ source: BaseToneSource) {
        guard !captureBusy, calibrationDraft == nil else { return }
        do {
            guard let index = project.gear.firstIndex(where: { $0.id == project.selectedGuitarID }) else { throw GearError.missingConfiguration }
            var next = project; next.gear[index].activeSource = source; try commit(next)
        } catch { self.error = error.localizedDescription }
    }
    func selectCalibration(_ id: UUID?) {
        guard let id, !captureBusy, calibrationDraft == nil else { return }
        do {
            guard let index = project.gear.firstIndex(where: { $0.id == project.selectedGuitarID }) else { throw GearError.missingConfiguration }
            var next = project
            try next.gear[index].selectCalibration(id)
            try commit(next)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func recordCalibration() {
        guard running, !captureBusy, calibrationDraft == nil, let config = selectedGuitar, let queue else {
            error = "Start audio and select a saved guitar configuration before recording."
            return
        }
        guard captureContext.path != .unspecified else {
            error = CalibrationError.signalPathRequired.localizedDescription
            return
        }
        drainSamples() // Discard pre-recording backlog on the consumer thread.
        captureSamples = []; captureSamples.reserveCapacity(441_000 * (route.stereo ? 2 : 1))
        captureGuitarID = config.id; captureRoute = route; recordedContext = captureContext
        captureDropBaseline = tr_queue_dropped(queue); captureToken = UUID()
        captureProgress = 0; captureStage = .recording; error = nil
        calibrationMessage = "Play varied single notes and chords for 10 seconds. Keep the same pickup and controls."
    }
    func discardCapture() {
        captureToken = UUID(); captureSamples = []; calibrationDraft = nil
        captureStage = .idle; captureProgress = 0
        calibrationMessage = "Unsaved recording discarded. Your saved Base Tone was preserved."
    }
    func saveCalibration(replacing: Bool) {
        guard let draft = calibrationDraft, !captureBusy else { return }
        do {
            guard let index = project.gear.firstIndex(where: { $0.id == draft.guitarID }), let store else { throw GearError.missingConfiguration }
            var next = project
            try next.gear[index].save(draft.record, replacing: replacing)
            try store.saveCapture(draft)
            try commit(next)
            calibrationDraft = nil; captureStage = .idle; captureProgress = 0
            calibrationMessage = "Base Tone saved locally. It stays selected until you explicitly replace it or choose another source."
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func drainSamples() {
        guard let queue else { return }
        let count = scratch.withUnsafeMutableBufferPointer { tr_queue_pop(queue, $0.baseAddress, UInt32($0.count)) }
        guard captureStage == .recording else { return }
        let total = 441_000 * (captureRoute.stereo ? 2 : 1)
        let remaining = total - captureSamples.count
        captureSamples.append(contentsOf: scratch.prefix(min(Int(count), remaining)))
        captureProgress = Double(captureSamples.count) / Double(total)
        if captureSamples.count == total { analyzeCapture(lostFrames: tr_queue_dropped(queue) != captureDropBaseline) }
    }
    private func analyzeCapture(lostFrames: Bool) {
        guard let guitarID = captureGuitarID else { discardCapture(); return }
        let samples = captureSamples; captureSamples = []
        let token = captureToken, route = captureRoute, context = recordedContext
        captureStage = .analyzing; calibrationMessage = "Analyzing your actual recording locally…"
        Task {
            do {
                let draft = try await Task.detached(priority: .userInitiated) {
                    try CalibrationAnalyzer.analyze(samples: samples, guitarID: guitarID, route: route,
                        context: context, lostFrames: lostFrames, invalidSamples: false)
                }.value
                guard self.captureToken == token else { return }
                self.calibrationDraft = draft; self.captureStage = .ready
                self.calibrationMessage = "Recording ready. Review it, then explicitly save or discard. Your saved Base Tone has not changed."
            } catch {
                guard self.captureToken == token else { return }
                self.captureStage = .idle; self.captureProgress = 0; self.error = error.localizedDescription
                self.calibrationMessage = "Recording was not saved. Your existing Base Tone was preserved."
            }
        }
    }

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
                throw AudioFailure.message("Use one duplex interface for input and output. Separate-device clock alignment is not validated yet.")
            }
            guard tr_route_valid(route.inputChannel, input.inputs) != 0, output.outputs > 0 else {
                throw AudioFailure.message("Select an available guitar input and an interface with output channels.")
            }
            guard !route.stereo || route.inputChannel + 1 < input.inputs else {
                throw AudioFailure.message("Choose a complete stereo input pair.")
            }
            guard route.outputChannel < output.outputs, route.outputChannel + 1 < output.outputs else {
                throw AudioFailure.message("Choose an available two-channel listening/output pair.")
            }
            guard tr_rate_supported(try Devices.rate(input.id)) != 0 else {
                throw AudioFailure.message("Set this interface to 44,100 Hz in Audio MIDI Setup, then try again. The app does not change your hardware rate silently.")
            }
            guard let meter = tr_meter_create() else { throw AudioFailure.message("Audio telemetry could not be allocated.") }
            self.meter = meter
            guard let queue = tr_queue_create(65_536) else { throw AudioFailure.message("Audio capture queue could not be allocated.") }
            self.queue = queue
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
                  format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
                throw AudioFailure.message("The audio graph must expose noninterleaved Float32 input and 44.1 kHz input/output. Check Audio MIDI Setup.")
            }
            let stereoInput = route.stereo
            guard let captureFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: stereoInput ? 2 : 1),
                  let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2) else {
                throw AudioFailure.message("Could not create the canonical audio format.")
            }
            engine.connect(inputNode, to: engine.mainMixerNode, format: captureFormat)
            engine.connect(engine.mainMixerNode, to: outputNode, format: playbackFormat)
            // Explicit channel maps: input pair and speaker output pair are independent.
            var map = stereoInput ? [Int32(route.inputChannel), Int32(route.inputChannel + 1)] : [Int32(route.inputChannel)]
            try map.withUnsafeMutableBytes { raw in
                try Devices.checked(AudioUnitSetProperty(inputUnit, kAudioOutputUnitProperty_ChannelMap,
                    kAudioUnitScope_Output, 1, raw.baseAddress!, UInt32(raw.count)), "Select guitar channel")
            }
            var outputMap = [Int32](repeating: -1, count: Int(output.outputs))
            outputMap[Int(route.outputChannel)] = 0; outputMap[Int(route.outputChannel + 1)] = 1
            try outputMap.withUnsafeMutableBytes { raw in
                try Devices.checked(AudioUnitSetProperty(outputUnit, kAudioOutputUnitProperty_ChannelMap,
                    kAudioUnitScope_Input, 0, raw.baseAddress!, UInt32(raw.count)), "Select listening output pair")
            }
            engine.mainMixerNode.outputVolume = 0
            inputNode.installTap(onBus: 0, bufferSize: 256, format: captureFormat) { buffer, _ in
                guard let data = buffer.floatChannelData else { return }
                if stereoInput {
                    tr_meter_process_pair(meter, data[0], data[1], buffer.frameLength)
                    tr_queue_push_pair(queue, data[0], data[1], buffer.frameLength)
                } else {
                    tr_meter_process(meter, data[0], buffer.frameLength)
                    tr_queue_push(queue, data[0], buffer.frameLength)
                }
            }
            tapInstalled = true
            engine.prepare(); try engine.start()
            running = true; monitoring = false
            let inputLabel = stereoInput ? "Inputs \(route.inputChannel + 1)/\(route.inputChannel + 2)" : "Input \(route.inputChannel + 1)"
            status = "Live • 44.1 kHz • \(input.name) • \(inputLabel) → Outputs \(route.outputChannel + 1)/\(route.outputChannel + 2)"
            timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self, let meter = self.meter else { return }
                self.peak = tr_meter_peak(meter); self.rms = tr_meter_rms(meter)
                self.frames = tr_meter_frames(meter); self.invalid = tr_meter_invalid(meter)
                self.drainSamples()
                if self.engine?.isRunning != true { self.stop(); self.error = "Audio stopped. Check the interface connection and restart audio." }
                else if (try? Devices.rate(input.id)) != 44_100 {
                    self.stop(); self.error = "Interface disconnected or sample rate changed. Restore 44.1 kHz and restart audio."
                }
            }
        } catch { stop(); self.error = error.localizedDescription }
    }
    func stop() {
        if captureBusy { discardCapture(); calibrationMessage = "Recording canceled because audio stopped. Saved Base Tone preserved." }
        timer?.cancel(); timer = nil
        engine?.mainMixerNode.outputVolume = 0
        engine?.stop()
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine = nil
        if let meter { tr_meter_destroy(meter) }; meter = nil
        if let queue { tr_queue_destroy(queue) }; queue = nil
        running = false; monitoring = false; peak = 0; rms = 0
        status = "Audio stopped. Routing settings are saved locally."
    }
}
