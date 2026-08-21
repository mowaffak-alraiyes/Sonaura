import Foundation

/// Test ear selection
enum TestEar: String, CaseIterable, Identifiable, Codable {
    case left, right, both
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .left: return "Left Ear"
        case .right: return "Right Ear"
        case .both: return "Both Ears"
        }
    }
}

/// Represents one frequency/ear combination to test
struct HearingTestStep: Identifiable, Hashable, Codable {
    let id: UUID
    let frequencyHz: Int
    let ear: TestEar
    let sequenceNumber: Int // Order in test sequence
    
    init(frequencyHz: Int, ear: TestEar, sequenceNumber: Int = 0) {
        self.id = UUID()
        self.frequencyHz = frequencyHz
        self.ear = ear
        self.sequenceNumber = sequenceNumber
    }
}

/// Response to a single tone presentation during threshold detection
struct TonePresentation: Identifiable, Codable, Equatable {
    let id: UUID
    let frequencyHz: Int
    let ear: TestEar
    let levelDB: Double // Presentation level in dB HL
    let heard: Bool
    let timestamp: Date
    
    init(frequencyHz: Int, ear: TestEar, levelDB: Double, heard: Bool) {
        self.id = UUID()
        self.frequencyHz = frequencyHz
        self.ear = ear
        self.levelDB = levelDB
        self.heard = heard
        self.timestamp = Date()
    }
}

/// Hearing threshold category from 4-level screening protocol
enum ThresholdCategory: String, Codable, Equatable {
    case excellentHearing = "≤15 dB HL"      // Excellent hearing range
    case normalHearing = "15-25 dB HL"       // Normal hearing range
    case mildLoss = "25-40 dB HL"            // Boundary of mild vs moderate loss
    case moderateLoss = "40-55 dB HL"        // Upper moderate region
    case moderateSevereOrWorse = "≥55 dB HL" // Likely moderately severe or worse
    
    /// Map category to approximate threshold value for ISO 7029 calculations
    ///
    /// For percentile calculations, we use midpoint estimates for each range:
    /// - "≤15 dB HL": Use 7.5 dB HL (midpoint of 0-15 range) - excellent hearing
    /// - "15-25 dB HL": Use 20 dB HL (midpoint of 15-25 range) - normal hearing
    /// - "25-40 dB HL": Use 32.5 dB HL (midpoint of 25-40 range) - mild loss
    /// - "40-55 dB HL": Use 47.5 dB HL (midpoint of 40-55 range) - moderate loss
    /// - "≥55 dB HL": Use 70 dB HL (conservative estimate) - user didn't hear at 55 dB HL
    var approximateThresholdDB: Double {
        switch self {
        case .excellentHearing: return 7.5   // Midpoint of 0-15 dB HL range
        case .normalHearing: return 20.0     // Midpoint of 15-25 dB HL range
        case .mildLoss: return 32.5           // Midpoint of 25-40 dB HL range
        case .moderateLoss: return 47.5       // Midpoint of 40-55 dB HL range
        case .moderateSevereOrWorse: return 70.0  // Conservative estimate - user didn't hear at 55 dB HL
        }
    }
    
    /// Display name for UI
    var displayName: String {
        return rawValue
    }

    /// The user-facing label after the v2 reframe (PRD.md §3.1). Descriptive,
    /// not diagnostic: says what was observed, never a clinical band or a
    /// "loss" verdict. `displayName`/`rawValue` (the dB HL band itself) still
    /// exist for anywhere that genuinely needs the clinical string — an
    /// expandable "for the curious" detail, the PDF export's fine print — but
    /// the default surface should read `gentleLabel`.
    var gentleLabel: String {
        switch self {
        case .excellentHearing: return "Sharp response"
        case .normalHearing: return "Typical response"
        case .mildLoss: return "Softer response"
        case .moderateLoss: return "Noticeably reduced response"
        case .moderateSevereOrWorse: return "Much reduced response — worth a real checkup"
        }
    }

    /// Which side of the reframed "steady / worth a look" vocabulary this
    /// category falls on (SonauraResultTone, in DesignSystem/SonauraTheme.swift).
    /// Kept as a plain string here rather than importing SwiftUI into a model
    /// file; the view layer maps it to a color.
    var gentleTone: String {
        switch self {
        case .excellentHearing, .normalHearing, .mildLoss: return "steady"
        case .moderateLoss, .moderateSevereOrWorse: return "attention"
        }
    }
}

/// Complete threshold result for one frequency/ear combination
struct ThresholdResult: Identifiable, Codable, Equatable {
    let id: UUID
    let frequencyHz: Int
    let ear: TestEar
    let thresholdDB: Double // Approximate hearing threshold in dB HL (from category)
    let category: ThresholdCategory? // Category from 3-level screening (optional for backward compatibility)
    let presentations: [TonePresentation] // All presentations that led to this threshold
    let timestamp: Date
    let reliability: ReliabilityLevel
    
    init(frequencyHz: Int, ear: TestEar, thresholdDB: Double, presentations: [TonePresentation], reliability: ReliabilityLevel = .standard, category: ThresholdCategory? = nil) {
        self.id = UUID()
        self.frequencyHz = frequencyHz
        self.ear = ear
        self.thresholdDB = thresholdDB
        self.category = category
        self.presentations = presentations
        self.timestamp = Date()
        self.reliability = reliability
    }
    
    /// Create from category (3-level screening protocol)
    init(frequencyHz: Int, ear: TestEar, category: ThresholdCategory, presentations: [TonePresentation]) {
        self.id = UUID()
        self.frequencyHz = frequencyHz
        self.ear = ear
        self.category = category
        self.thresholdDB = category.approximateThresholdDB
        self.presentations = presentations
        self.timestamp = Date()
        self.reliability = .standard
    }
    
    enum ReliabilityLevel: String, Codable, Equatable {
        case excellent = "Excellent"
        case good = "Good"
        case standard = "Standard"
        case poor = "Poor"
    }
}

/// Complete test session with all results
struct HearingTestSession: Identifiable, Codable, Equatable {
    let id: UUID
    let results: [ThresholdResult]
    let startTime: Date
    let endTime: Date
    let deviceModel: String // e.g., "AirPods Pro"
    let userAge: Int?
    let userGender: ISO7029Calculator.Gender?
    
    init(results: [ThresholdResult], startTime: Date, endTime: Date, deviceModel: String, userAge: Int? = nil, userGender: ISO7029Calculator.Gender? = nil) {
        self.id = UUID()
        self.results = results
        self.startTime = startTime
        self.endTime = endTime
        self.deviceModel = deviceModel
        self.userAge = userAge
        self.userGender = userGender
    }
    
    /// Pure Tone Average (average of 500, 1k, 2k, 4k Hz)
    func pureToneAverage(ear: TestEar) -> Double? {
        let ptaFreqs = [500, 1000, 2000, 4000]
        let earResults = results.filter { $0.ear == ear && ptaFreqs.contains($0.frequencyHz) }
        guard earResults.count == 4 else { return nil }
        return earResults.map { $0.thresholdDB }.reduce(0, +) / 4.0
    }
    
    /// Overall hearing classification based on PTA
    func overallClassification(ear: TestEar) -> HearingClassification {
        guard let pta = pureToneAverage(ear: ear) else {
            return .normal // Default if PTA can't be calculated
        }
        return ISO7029Calculator.classify(thresholdDB: pta)
    }
    
    /// Get all results for a specific ear
    func results(for ear: TestEar) -> [ThresholdResult] {
        return results.filter { $0.ear == ear }.sorted { $0.frequencyHz < $1.frequencyHz }
    }
}
