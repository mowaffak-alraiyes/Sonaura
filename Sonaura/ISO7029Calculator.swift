import Foundation

/// ISO 7029:2017 - Statistical distribution of hearing thresholds related to age
/// Provides age- and gender-specific hearing threshold percentiles for otologically normal populations
/// Frequencies: 125 Hz to 12.5 kHz; Ages: 18-80 years
struct ISO7029Calculator {
    
    enum Gender: String, Codable {
        case male
        case female
    }
    
    /// Calculate expected median hearing threshold (dB HL) for a given age, frequency, and gender
    /// Based on ISO 7029:2017 formulae
    /// - Parameters:
    ///   - age: Age in years (18-80)
    ///   - frequency: Frequency in Hz (125-12500)
    ///   - gender: Male or female
    /// - Returns: Median threshold in dB HL (0 dB HL = normal 18-year-old median)
    static func medianThreshold(age: Int, frequency: Int, gender: Gender) -> Double {
        guard age >= 18 && age <= 80 else { return 0.0 }
        
        let Y = Double(age)
        let alpha = alphaParameter(frequency: frequency, gender: gender)
        let beta = betaParameter(frequency: frequency)
        
        // ISO 7029 formula: H_median = alpha * (Y - 18)^2 + beta * (Y - 18)
        let ageFactor = Y - 18.0
        return alpha * pow(ageFactor, 2) + beta * ageFactor
    }
    
    /// Calculate standard deviation of hearing threshold distribution at given age/frequency
    static func standardDeviation(age: Int, frequency: Int, gender: Gender) -> Double {
        // ISO 7029 specifies standard deviation increases with age
        // Simplified model: SD ≈ 5-15 dB depending on frequency and age
        let baseSD = baseStandardDeviation(frequency: frequency)
        let ageFactor = min(1.5, 1.0 + Double(age - 18) / 100.0)
        return baseSD * ageFactor
    }
    
    /// Calculate the percentile of a measured threshold relative to age-matched norms
    /// - Returns: Percentile (0-99.9), where 50 = median, >50 = worse than average, <50 = better
    /// - Note: Percentiles are capped at 99.9th percentile (statistically, 100th percentile is not meaningful)
    static func percentile(
        measuredThreshold: Double,
        age: Int,
        frequency: Int,
        gender: Gender
    ) -> Double {
        let median = medianThreshold(age: age, frequency: frequency, gender: gender)
        let sd = standardDeviation(age: age, frequency: frequency, gender: gender)
        
        // Z-score: how many standard deviations from median
        let z = (measuredThreshold - median) / sd
        
        // Convert Z to percentile using cumulative normal distribution
        let rawPercentile = cumulativeNormalDistribution(z: z) * 100.0
        
        // Cap at 99.9th percentile (100th percentile is not statistically meaningful)
        // This handles cases where thresholds are very high (e.g., didn't hear at max test level)
        return min(rawPercentile, 99.9)
    }
    
    /// Classify hearing level based on dB HL threshold
    /// Standard audiometric classification
    static func classify(thresholdDB: Double) -> HearingClassification {
        switch thresholdDB {
        case ..<(-10):
            return .exceptional
        case -10..<16:
            return .normal
        case 16..<26:
            return .normalVariation
        case 26..<41:
            return .mild
        case 41..<56:
            return .moderate
        case 56..<71:
            return .moderatelySevere
        case 71..<91:
            return .severe
        default:
            return .profound
        }
    }
    
    /// Calculate Pure Tone Average (PTA) - average of 500, 1000, 2000, 4000 Hz
    /// This is the standard metric used for overall hearing assessment
    static func pureToneAverage(thresholds: [Int: Double]) -> Double? {
        let ptaFrequencies = [500, 1000, 2000, 4000]
        let values = ptaFrequencies.compactMap { thresholds[$0] }
        guard values.count == 4 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
    
    // MARK: - ISO 7029 Parameters
    
    /// Alpha parameter (quadratic age coefficient) from ISO 7029
    /// Gender-specific values
    private static func alphaParameter(frequency: Int, gender: Gender) -> Double {
        // Simplified model derived from ISO 7029 tables
        // Alpha increases with frequency (high frequencies degrade faster with age)
        switch gender {
        case .male:
            switch frequency {
            case 125: return 0.0001
            case 250: return 0.0002
            case 500: return 0.0004
            case 1000: return 0.0008
            case 2000: return 0.0015
            case 3000: return 0.0025
            case 4000: return 0.0040
            case 6000: return 0.0060
            case 8000: return 0.0090
            case 12000: return 0.0150
            default: return interpolateAlpha(frequency: frequency, gender: gender)
            }
        case .female:
            // Females generally have better high-frequency hearing preservation
            switch frequency {
            case 125: return 0.0001
            case 250: return 0.0002
            case 500: return 0.0003
            case 1000: return 0.0006
            case 2000: return 0.0010
            case 3000: return 0.0018
            case 4000: return 0.0030
            case 6000: return 0.0045
            case 8000: return 0.0070
            case 12000: return 0.0120
            default: return interpolateAlpha(frequency: frequency, gender: gender)
            }
        }
    }
    
    /// Beta parameter (linear age coefficient) from ISO 7029
    private static func betaParameter(frequency: Int) -> Double {
        // Beta is small or negative at low frequencies (slight improvement possible)
        // Positive and larger at high frequencies
        switch frequency {
        case 125: return -0.01
        case 250: return 0.0
        case 500: return 0.02
        case 1000: return 0.05
        case 2000: return 0.10
        case 3000: return 0.15
        case 4000: return 0.20
        case 6000: return 0.30
        case 8000: return 0.45
        case 12000: return 0.70
        default: return interpolateBeta(frequency: frequency)
        }
    }
    
    /// Base standard deviation at age 18
    private static func baseStandardDeviation(frequency: Int) -> Double {
        // SD typically 5-8 dB at low frequencies, increases to 10-15 dB at high frequencies
        if frequency <= 500 { return 6.0 }
        if frequency <= 2000 { return 7.0 }
        if frequency <= 4000 { return 9.0 }
        if frequency <= 8000 { return 12.0 }
        return 15.0
    }
    
    // MARK: - Helper Functions
    
    private static func interpolateAlpha(frequency: Int, gender: Gender) -> Double {
        // Simple log interpolation between known frequencies
        let freqs = [125, 250, 500, 1000, 2000, 4000, 8000, 12000]
        for i in 0..<freqs.count-1 {
            if frequency >= freqs[i] && frequency <= freqs[i+1] {
                let f1 = Double(freqs[i])
                let f2 = Double(freqs[i+1])
                let alpha1 = alphaParameter(frequency: freqs[i], gender: gender)
                let alpha2 = alphaParameter(frequency: freqs[i+1], gender: gender)
                let ratio = (Double(frequency) - f1) / (f2 - f1)
                return alpha1 + (alpha2 - alpha1) * ratio
            }
        }
        return 0.001
    }
    
    private static func interpolateBeta(frequency: Int) -> Double {
        let freqs = [125, 250, 500, 1000, 2000, 4000, 8000, 12000]
        for i in 0..<freqs.count-1 {
            if frequency >= freqs[i] && frequency <= freqs[i+1] {
                let f1 = Double(freqs[i])
                let f2 = Double(freqs[i+1])
                let beta1 = betaParameter(frequency: freqs[i])
                let beta2 = betaParameter(frequency: freqs[i+1])
                let ratio = (Double(frequency) - f1) / (f2 - f1)
                return beta1 + (beta2 - beta1) * ratio
            }
        }
        return 0.1
    }
    
    /// Cumulative standard normal distribution approximation
    /// Converts Z-score to percentile (0-1)
    private static func cumulativeNormalDistribution(z: Double) -> Double {
        // Abramowitz and Stegun approximation (accurate to ~0.0001)
        let t = 1.0 / (1.0 + 0.2316419 * abs(z))
        let d = 0.3989423 * exp(-z * z / 2.0)
        let probability = d * t * (0.3193815 + t * (-0.3565638 + t * (1.781478 + t * (-1.821256 + t * 1.330274))))
        
        return z >= 0 ? 1.0 - probability : probability
    }
}

/// Hearing classification categories based on Pure Tone Average (PTA) or individual thresholds
enum HearingClassification: String, CaseIterable {
    case exceptional = "Exceptional"           // < -10 dB HL
    case normal = "Normal"                     // -10 to 15 dB HL
    case normalVariation = "Normal Variation"  // 16 to 25 dB HL
    case mild = "Mild Loss"                    // 26 to 40 dB HL
    case moderate = "Moderate Loss"            // 41 to 55 dB HL
    case moderatelySevere = "Moderately Severe Loss"  // 56 to 70 dB HL
    case severe = "Severe Loss"                // 71 to 90 dB HL
    case profound = "Profound Loss"            // > 90 dB HL
    
    var description: String {
        switch self {
        case .exceptional:
            return "Better than average hearing for young adults."
        case .normal:
            return "Within normal hearing range. No difficulty hearing normal speech."
        case .normalVariation:
            return "Slightly elevated but within normal range. May have minimal difficulty in noisy environments."
        case .mild:
            return "Mild hearing loss. Difficulty hearing soft speech or in noisy situations."
        case .moderate:
            return "Moderate hearing loss. May miss normal conversation, especially in groups."
        case .moderatelySevere:
            return "Moderately severe hearing loss. Most speech is difficult without amplification."
        case .severe:
            return "Severe hearing loss. Cannot understand speech without hearing aids."
        case .profound:
            return "Profound hearing loss. May not hear most sounds without cochlear implants."
        }
    }
    
    var color: String {
        switch self {
        case .exceptional, .normal:
            return "green"
        case .normalVariation:
            return "blue"
        case .mild:
            return "yellow"
        case .moderate:
            return "orange"
        case .moderatelySevere, .severe:
            return "red"
        case .profound:
            return "purple"
        }
    }
}
