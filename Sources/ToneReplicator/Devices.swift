import CoreAudio
import Foundation

struct AudioDevice: Identifiable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let inputs: UInt32
    let outputs: UInt32
    let rate: Double
}

enum AudioFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(s) = self { return s }; return nil }
}

enum Devices {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func checked(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else { throw AudioFailure.message("\(operation) failed (CoreAudio \(status)).") }
    }
    static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) throws -> String {
        var a = address(selector); var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        try checked(AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value), "Read device identity")
        return value as String
    }
    static func rate(_ device: AudioDeviceID) throws -> Double {
        var a = address(kAudioDevicePropertyNominalSampleRate); var value: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        try checked(AudioObjectGetPropertyData(device, &a, 0, nil, &size, &value), "Read sample rate")
        return value
    }
    static func channels(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> UInt32 {
        var a = address(kAudioDevicePropertyStreamConfiguration, scope: scope); var size: UInt32 = 0
        try checked(AudioObjectGetPropertyDataSize(device, &a, 0, nil, &size), "Read channel configuration size")
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        try checked(AudioObjectGetPropertyData(device, &a, 0, nil, &size, buffer), "Read channels")
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
            .reduce(0) { $0 + $1.mNumberChannels }
    }
    static func discover() throws -> [AudioDevice] {
        var a = address(kAudioHardwarePropertyDevices); var size: UInt32 = 0
        try checked(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size), "Discover devices")
        var ids = [AudioDeviceID](repeating: 0, count: Int(size)/MemoryLayout<AudioDeviceID>.size)
        if ids.isEmpty { return [] }
        try ids.withUnsafeMutableBytes { raw in
            try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, raw.baseAddress!), "List devices")
        }
        return try ids.map { id in
            AudioDevice(id: id, uid: try string(id, kAudioDevicePropertyDeviceUID),
                name: try string(id, kAudioObjectPropertyName),
                inputs: try channels(id, scope: kAudioObjectPropertyScopeInput),
                outputs: try channels(id, scope: kAudioObjectPropertyScopeOutput), rate: try rate(id))
        }.sorted { $0.name < $1.name }
    }
}
