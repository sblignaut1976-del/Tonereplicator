import Foundation

enum BaseToneSource: String, Codable, CaseIterable {
    case factory = "Verified Factory Data"
    case calibration = "My Calibration"
}

struct GuitarIdentity: Codable, Equatable {
    var manufacturer = ""
    var family = ""
    var model = ""
    var variant = ""
    var year = ""
    var pickupModel = ""
    var pickupPosition = ""
    var switchingMode = ""
    var sourceURL = ""
    var identificationStatus = "USER PROVIDED"
    static func fenderTemplate() -> GuitarIdentity {
        var value = GuitarIdentity()
        value.manufacturer = "Fender"; value.family = "Telecaster"
        value.model = "Player II Modified Telecaster SH"
        value.pickupModel = "Player II Noiseless Tele"; value.pickupPosition = "Bridge"
        value.switchingMode = "Factory wiring"
        value.sourceURL = "https://www.fender.com/products/player-ii-modified-telecaster-sh"
        value.identificationStatus = "TEMPLATE — USER MUST CONFIRM"
        return value
    }
    var complete: Bool {
        [manufacturer, model, pickupPosition].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var title: String { "\(manufacturer) \(model) · \(pickupPosition)" }
}

enum CalibrationPath: String, Codable, CaseIterable {
    case unspecified = "Choose signal path"
    case direct = "Guitar → interface instrument input"
    case kemperBypass = "Guitar → Kemper Stage bypass → interface line input"
    case other = "Other documented path"
}

struct CaptureContext: Codable, Equatable {
    var guitarVolume = ""
    var guitarTone = ""
    var interfaceGainNote = ""
    var path: CalibrationPath = .unspecified
    var deviceNote = ""
    var firmwareNote = ""
    var outputNote = ""

    init(path: CalibrationPath = .unspecified) { self.path = path }
    enum CodingKeys: String, CodingKey {
        case guitarVolume, guitarTone, interfaceGainNote, path, deviceNote, firmwareNote, outputNote
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guitarVolume = try c.decode(String.self, forKey: .guitarVolume)
        guitarTone = try c.decode(String.self, forKey: .guitarTone)
        interfaceGainNote = try c.decode(String.self, forKey: .interfaceGainNote)
        path = try c.decodeIfPresent(CalibrationPath.self, forKey: .path) ?? .unspecified
        deviceNote = try c.decodeIfPresent(String.self, forKey: .deviceNote) ?? ""
        firmwareNote = try c.decodeIfPresent(String.self, forKey: .firmwareNote) ?? ""
        outputNote = try c.decodeIfPresent(String.self, forKey: .outputNote) ?? ""
    }
}

struct CalibrationFingerprint: Codable, Equatable {
    let algorithm: String
    let sampleRate: Int
    let frames: Int
    let peak: Double
    let rms: Double
    let dc: Double
    let bandDB: [Double]
    var stereoCorrelation: Double? = nil
}

struct SavedCalibration: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let fingerprint: CalibrationFingerprint
    let wavFilename: String
    let interfaceUID: String
    let inputChannel: UInt32
    let context: CaptureContext
    var channels: Int? = nil
    var channelCount: Int { channels ?? 1 }
}

struct GuitarConfiguration: Codable, Equatable, Identifiable {
    let id: UUID
    let identity: GuitarIdentity
    var activeSource: BaseToneSource = .calibration
    var activeCalibrationID: UUID? = nil
    var calibrations: [SavedCalibration] = []
    var baseTone: SavedCalibration? { calibrations.first { $0.id == activeCalibrationID } }

    mutating func selectCalibration(_ id: UUID) throws {
        guard calibrations.contains(where: { $0.id == id }) else { throw GearError.missingCalibration }
        activeCalibrationID = id
        activeSource = .calibration
    }

    mutating func save(_ calibration: SavedCalibration, replacing: Bool) throws {
        if activeCalibrationID != nil && !replacing { throw GearError.replacementRequired }
        guard !calibrations.contains(where: { $0.id == calibration.id }) else { throw GearError.duplicateCapture }
        calibrations.append(calibration) // Prior capture/history is retained on replacement.
        activeCalibrationID = calibration.id
        activeSource = .calibration
    }
}

enum GearError: LocalizedError {
    case replacementRequired, duplicateCapture, missingConfiguration, missingCalibration, incompleteIdentity
    var errorDescription: String? {
        switch self {
        case .replacementRequired: return "A Base Tone is already saved. Choose Replace Base Tone explicitly."
        case .duplicateCapture: return "This capture is already saved."
        case .missingConfiguration: return "Select a saved guitar/pickup configuration."
        case .missingCalibration: return "Choose a calibration saved for this guitar/pickup configuration."
        case .incompleteIdentity: return "Enter manufacturer, model and pickup position."
        }
    }
}
