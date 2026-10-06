import Foundation

enum EvidenceStatus: String, Codable, CaseIterable {
    case verified = "VERIFIED"
    case corroborated = "CORROBORATED"
    case unverified = "UNVERIFIED — WEB RESEARCH"
    case unknown = "UNKNOWN"
}

struct TargetClaim: Codable, Equatable, Identifiable {
    var id = UUID()
    var topic = ""
    var claim = ""
    var status = EvidenceStatus.unknown
    var source = ""
    var sourceVersion = ""
    var assessedAt = Date()
    var assessment = "User assessment"
    func validate() throws {
        guard !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !claim.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              status == .unknown || !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !assessment.isEmpty else { throw TargetError.invalidEvidence }
    }
}

struct TargetReference: Codable, Equatable, Identifiable {
    let id: UUID
    let importedAt: Date
    var title: String
    var artist = ""
    var recordingVersion = ""
    var part = ""
    let originalFilename: String
    let sourceName: String
    let originalSHA256: String
    let originalSampleRate: Double
    let channels: Int
    let startSeconds: Double
    let sourceFrames: Int64
    let conversion: String
    let analysisSHA256: String
    let fingerprint: CalibrationFingerprint
    var claims: [TargetClaim] = []
    var duration: Double { Double(fingerprint.frames) / 44_100 }
    func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              originalFilename == URL(fileURLWithPath: originalFilename).lastPathComponent,
              originalFilename.hasPrefix("original."),
              !sourceName.isEmpty,
              originalSHA256.count == 64, analysisSHA256.count == 64,
              originalSampleRate.isFinite, (8_000...192_000).contains(originalSampleRate),
              channels == 1 || channels == 2, startSeconds.isFinite, startSeconds >= 0,
              sourceFrames > 0, fingerprint.sampleRate == 44_100,
              (2048...1_323_000).contains(fingerprint.frames), fingerprint.bandDB.count == 24,
              fingerprint.bandDB.allSatisfy(\.isFinite),
              [fingerprint.peak, fingerprint.rms, fingerprint.dc].allSatisfy(\.isFinite),
              Set(claims.map(\.id)).count == claims.count else { throw TargetError.invalidLibrary }
        if let c = fingerprint.stereoCorrelation {
            guard c.isFinite, (-1...1).contains(c) else { throw TargetError.invalidLibrary }
        }
        for claim in claims { try claim.validate() }
    }
}

struct TargetLibrary: Codable, Equatable {
    var schemaVersion = 1
    var references: [TargetReference] = []
    var selectedID: UUID? = nil
    var selected: TargetReference? { references.first { $0.id == selectedID } }
    func validate() throws {
        guard schemaVersion == 1, Set(references.map(\.id)).count == references.count,
              selectedID == nil || selected != nil else { throw TargetError.invalidLibrary }
        for reference in references { try reference.validate() }
    }
}

enum TargetError: LocalizedError {
    case invalidLibrary, invalidEvidence, invalidClip, unsupportedAudio, conversionFailed, invalidAudio, missingTarget
    var errorDescription: String? {
        switch self {
        case .invalidLibrary: return "Saved target data is invalid or needs a newer app. The original was preserved."
        case .invalidEvidence: return "Enter a topic and claim. Add a source for any status other than UNKNOWN."
        case .invalidClip: return "Choose a start inside the file and a section of 1–30 seconds that fits in the recording."
        case .unsupportedAudio: return "Choose a decodable mono or stereo audio file at 8–192 kHz."
        case .conversionFailed: return "The reference could not be converted to 44.1 kHz. Your source file is unchanged."
        case .invalidAudio: return "The selected section contains invalid samples or no usable audio. Choose another section."
        case .missingTarget: return "Select an imported target first."
        }
    }
}

struct TargetStore {
    let root: URL
    var url: URL { root.appendingPathComponent("targets.json") }
    var assets: URL { root.appendingPathComponent("Targets", isDirectory: true) }
    func load() throws -> TargetLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return TargetLibrary() }
        let library = try JSONDecoder().decode(TargetLibrary.self, from: Data(contentsOf: url))
        try library.validate()
        return library
    }
    func save(_ library: TargetLibrary) throws {
        try library.validate()
        if FileManager.default.fileExists(atPath: url.path) { _ = try load() }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(library).write(to: url, options: .atomic)
    }
}
