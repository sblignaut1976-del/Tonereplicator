import Foundation

struct RoutingPreset: Codable, Equatable {
    var inputUID = ""
    var outputUID = ""
    var inputChannel: UInt32 = 0
    // DI/reamp routing is reserved data, not a claim of implemented reamping.
    var diChannel: UInt32? = nil
    var reampSend: UInt32? = nil
    var reampReturn: UInt32? = nil
}

struct Project: Codable, Equatable {
    var schemaVersion = 2
    var name = "My Tone Project"
    private(set) var analysisRate = 44_100
    var selectedInterfaceUID = ""
    var routingByInterface: [String: RoutingPreset] = [:]
    var gear: [GuitarConfiguration] = []
    var selectedGuitarID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion, name, analysisRate, selectedInterfaceUID, routingByInterface, gear, selectedGuitarID
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == 1 || version == 2 else { throw ProjectError.unsupportedSchema }
        guard try c.decode(Int.self, forKey: .analysisRate) == 44_100 else { throw ProjectError.invalidRate }
        name = try c.decode(String.self, forKey: .name)
        selectedInterfaceUID = try c.decode(String.self, forKey: .selectedInterfaceUID)
        routingByInterface = try c.decode([String: RoutingPreset].self, forKey: .routingByInterface)
        if version == 2 {
            gear = try c.decode([GuitarConfiguration].self, forKey: .gear)
            selectedGuitarID = try c.decodeIfPresent(UUID.self, forKey: .selectedGuitarID)
            guard Set(gear.map(\.id)).count == gear.count,
                  selectedGuitarID == nil || gear.contains(where: { $0.id == selectedGuitarID }) else {
                throw ProjectError.invalidGear
            }
            for config in gear {
                guard config.identity.complete,
                      Set(config.calibrations.map(\.id)).count == config.calibrations.count,
                      config.activeCalibrationID == nil || config.baseTone != nil else { throw ProjectError.invalidGear }
                for record in config.calibrations {
                    guard record.fingerprint.sampleRate == 44_100, record.fingerprint.bandDB.count == 24,
                          record.fingerprint.frames == 441_000,
                          record.wavFilename == "\(record.id.uuidString).wav",
                          [record.fingerprint.rms, record.fingerprint.peak, record.fingerprint.dc].allSatisfy(\.isFinite),
                          record.fingerprint.bandDB.allSatisfy(\.isFinite) else { throw ProjectError.invalidGear }
                }
            }
        }
        schemaVersion = 2
    }
}

enum ProjectError: LocalizedError {
    case unsupportedSchema, invalidRate, invalidGear
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return "This project needs a newer app. The original was preserved."
        case .invalidRate: return "This project does not use the required 44.1 kHz rate."
        case .invalidGear: return "Saved Gear Vault data is invalid. The original was preserved."
        }
    }
}

struct ProjectStore {
    let url: URL
    static func standard() throws -> ProjectStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return ProjectStore(url: base.appendingPathComponent("ToneReplicator/project.json"))
    }
    func load() throws -> Project {
        guard FileManager.default.fileExists(atPath: url.path) else { return Project() }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Project.self, from: data)
    }
    func save(_ project: Project) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let original = try Data(contentsOf: url)
            // Validate existing file before any write. Preserve schema-1 data on migration.
            _ = try JSONDecoder().decode(Project.self, from: original)
            let object = try JSONSerialization.jsonObject(with: original) as? [String: Any]
            if object?["schemaVersion"] as? Int == 1 {
                let backup = url.deletingLastPathComponent().appendingPathComponent("project-schema1-\(UUID().uuidString).json")
                try original.write(to: backup, options: .withoutOverwriting)
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        _ = try JSONDecoder().decode(Project.self, from: data)
        try data.write(to: url, options: .atomic)
    }
}
