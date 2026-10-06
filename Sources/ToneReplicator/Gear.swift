import Foundation

enum BaseToneSource: String, Codable, CaseIterable {
    case factory = "Verified Factory Data"
    case calibration = "My Calibration"
}

struct GuitarIdentity: Codable, Equatable {
    var manufacturer = "Fender"
    var family = "Telecaster"
    var model = "Player II Modified Telecaster SH"
    var variant = ""
    var year = ""
    var pickupModel = "Player II Noiseless Tele"
    var pickupPosition = "Bridge"
    var switchingMode = "Factory wiring"
    var sourceURL = "https://www.fender.com/products/player-ii-modified-telecaster-sh"
    // User supplied this link/identification; fetching/verifying it is a separate step.
    var identificationStatus = "USER VERIFIED — SOURCES SUPPLIED"
    var complete: Bool {
        [manufacturer, model, pickupPosition].allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    var title: String { "\(manufacturer) \(model) · \(pickupPosition)" }
}

struct CaptureContext: Codable, Equatable {
    var guitarVolume = ""
    var guitarTone = ""
    var interfaceGainNote = ""
}

struct CalibrationFingerprint: Codable, Equatable {
    let algorithm: String
    let sampleRate: Int
    let frames: Int
    let peak: Double
    let rms: Double
    let dc: Double
    let bandDB: [Double]
}

struct SavedCalibration: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let fingerprint: CalibrationFingerprint
    let wavFilename: String
    let interfaceUID: String
    let inputChannel: UInt32
    let context: CaptureContext
}

struct GuitarConfiguration: Codable, Equatable, Identifiable {
    let id: UUID
    let identity: GuitarIdentity
    var activeSource: BaseToneSource = .calibration
    var activeCalibrationID: UUID? = nil
    var calibrations: [SavedCalibration] = []
    var baseTone: SavedCalibration? { calibrations.first { $0.id == activeCalibrationID } }

    mutating func save(_ calibration: SavedCalibration, replacing: Bool) throws {
        if activeCalibrationID != nil && !replacing { throw GearError.replacementRequired }
        guard !calibrations.contains(where: { $0.id == calibration.id }) else { throw GearError.duplicateCapture }
        calibrations.append(calibration) // Prior capture/history is retained on replacement.
        activeCalibrationID = calibration.id
        activeSource = .calibration
    }
}

enum GearError: LocalizedError {
    case replacementRequired, duplicateCapture, missingConfiguration, incompleteIdentity
    var errorDescription: String? {
        switch self {
        case .replacementRequired: return "A Base Tone is already saved. Choose Replace Base Tone explicitly."
        case .duplicateCapture: return "This capture is already saved."
        case .missingConfiguration: return "Select a saved guitar/pickup configuration."
        case .incompleteIdentity: return "Enter manufacturer, model and pickup position."
        }
    }
}
