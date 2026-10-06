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
    var schemaVersion = 1
    var name = "My Tone Project"
    let analysisRate = 44_100
    var selectedInterfaceUID = ""
    var routingByInterface: [String: RoutingPreset] = [:]
}

enum ProjectError: LocalizedError {
    case unsupportedSchema, invalidRate
    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: return "This project needs a newer app. The original was preserved."
        case .invalidRate: return "This project does not use the required 44.1 kHz rate."
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
        // Validate before decoding: fixed Codable properties otherwise ignore incoming values.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["schemaVersion"] as? Int == 1 else { throw ProjectError.unsupportedSchema }
        guard object?["analysisRate"] as? Int == 44_100 else { throw ProjectError.invalidRate }
        return try JSONDecoder().decode(Project.self, from: data)
    }
    func save(_ project: Project) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: url, options: .atomic)
    }
}
