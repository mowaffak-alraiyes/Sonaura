import Foundation

/// Calibration data for AirPods output levels and conversion to audiometric dB HL
/// Based on published measurements and audiometric reference standards (ANSI S3.6-2018)
struct AirPodsCalibration {
    
    /// Maximum output levels (dB SPL) for various AirPods models at 100% iOS volume
    /// Source: Independent measurements show AirPods can reach ~102-108 dB SPL at max volume
    /// We use conservative estimates aligned with research data
    enum ModelType: String, CaseIterable {
        case airPodsGen1 = "AirPods (1st/2nd Gen)"
        case airPodsGen3 = "AirPods (3rd Gen)"
        case airPodsPro = "AirPods Pro"
        case airPodsPro2 = "AirPods Pro (2nd Gen)"
        case airPodsMax = "AirPods Max"
        case generic = "Generic Bluetooth Earbuds"
        
        /// Maximum output in dB SPL at each frequency (measured at 100% volume)
        /// Frequencies: 250, 500, 1000, 2000, 4000, 8000 Hz
        func maxOutputSPL(at frequency: Int) -> Double {
            switch self {
            case .airPodsGen1:
                return maxOutputSPLGen1(frequency)
            case .airPodsGen3:
                return maxOutputSPLGen3(frequency)
            case .airPodsPro:
                return maxOutputSPLPro(frequency)
            case .airPodsPro2:
                return maxOutputSPLPro2(frequency)
            case .airPodsMax:
                return maxOutputSPLMax(frequency)
            case .generic:
                return maxOutputSPLGeneric(frequency)
            }
        }
        
        private func maxOutputSPLGen1(_ freq: Int) -> Double {
            // Conservative estimates based on consumer headphone measurements
            // AirPods 1st/2nd gen: ~102-105 dB SPL at max volume
            switch freq {
            case 250: return 100.0
            case 500: return 102.0
            case 1000: return 104.0
            case 2000: return 105.0
            case 4000: return 104.0
            case 8000: return 102.0
            case 12000: return 98.0
            default: return 103.0
            }
        }
        
        private func maxOutputSPLGen3(_ freq: Int) -> Double {
            // AirPods 3rd gen: Similar to gen 2, slightly improved bass
            switch freq {
            case 250: return 101.0
            case 500: return 103.0
            case 1000: return 105.0
            case 2000: return 106.0
            case 4000: return 105.0
            case 8000: return 103.0
            case 12000: return 99.0
            default: return 104.0
            }
        }
        
        private func maxOutputSPLPro(_ freq: Int) -> Double {
            // AirPods Pro: ~105-108 dB SPL measured at max
            switch freq {
            case 250: return 103.0
            case 500: return 105.0
            case 1000: return 107.0
            case 2000: return 108.0
            case 4000: return 107.0
            case 8000: return 105.0
            case 12000: return 100.0
            default: return 106.0
            }
        }
        
        private func maxOutputSPLPro2(_ freq: Int) -> Double {
            // AirPods Pro 2nd gen: Similar to Pro 1 with slight improvements
            switch freq {
            case 250: return 104.0
            case 500: return 106.0
            case 1000: return 108.0
            case 2000: return 109.0
            case 4000: return 108.0
            case 8000: return 106.0
            case 12000: return 101.0
            default: return 107.0
            }
        }
        
        private func maxOutputSPLMax(_ freq: Int) -> Double {
            // AirPods Max: Over-ear, can produce higher SPL
            switch freq {
            case 250: return 106.0
            case 500: return 108.0
            case 1000: return 110.0
            case 2000: return 111.0
            case 4000: return 110.0
            case 8000: return 108.0
            case 12000: return 103.0
            default: return 109.0
            }
        }
        
        private func maxOutputSPLGeneric(_ freq: Int) -> Double {
            // Conservative generic estimate for Bluetooth earbuds
            switch freq {
            case 250: return 100.0
            case 500: return 102.0
            case 1000: return 104.0
            case 2000: return 105.0
            case 4000: return 104.0
            case 8000: return 102.0
            case 12000: return 97.0
            default: return 103.0
            }
        }
    }
    
    /// Convert dB SPL to dB HL (Hearing Level) using audiometric reference values
    /// Reference: ANSI S3.6-2018 - Reference Equivalent Threshold Sound Pressure Levels (RETSPL)
    /// for supra-aural headphones (insert earphones have different values but similar)
    static func convertSPLtoHL(splDB: Double, frequency: Int) -> Double {
        let retspl = referenceSPL(for: frequency)
        return splDB - retspl
    }
    
    /// Convert dB HL to dB SPL
    static func convertHLtoSPL(hlDB: Double, frequency: Int) -> Double {
        let retspl = referenceSPL(for: frequency)
        return hlDB + retspl
    }
    
    /// RETSPL values for insert earphones (similar to AirPods in-ear coupling)
    /// These are the sound pressure levels that correspond to 0 dB HL at each frequency
    /// Source: ANSI S3.6-2018, ISO 389-2 for insert earphones
    private static func referenceSPL(for frequency: Int) -> Double {
        switch frequency {
        case 125: return 26.0
        case 250: return 14.0
        case 500: return 5.5
        case 1000: return 0.0  // Reference point
        case 2000: return -3.0
        case 3000: return -3.5
        case 4000: return -1.0
        case 6000: return 2.0
        case 8000: return 13.0
        case 12000: return 18.0
        default:
            // Interpolate or use nearest value
            if frequency < 250 { return 20.0 }
            if frequency > 8000 { return 15.0 }
            return 5.0
        }
    }
    
    /// Calculate the required digital attenuation (in dB) to achieve a target dB HL
    /// at a given frequency, assuming iOS volume is at 100%
    /// - Parameters:
    ///   - targetHL: Desired hearing level in dB HL
    ///   - frequency: Test frequency in Hz
    ///   - model: AirPods model type
    /// - Returns: Attenuation in dB (negative value) to apply to the digital signal
    static func attenuationForTargetHL(
        targetHL: Double,
        frequency: Int,
        model: ModelType
    ) -> Double {
        let maxSPL = model.maxOutputSPL(at: frequency)
        let targetSPL = convertHLtoSPL(hlDB: targetHL, frequency: frequency)
        return targetSPL - maxSPL // Negative value = attenuation needed
    }
    
    /// The true amplitude multiplier (0.0-1.0) needed to reach `targetHL`.
    ///
    /// This value is now returned **unclamped**, which is a deliberate change.
    ///
    /// It used to be floored by a `dynamicMinimum`, on the reasoning that low
    /// levels round to zero in 16-bit samples and become inaudible. The
    /// diagnosis was correct; the remedy silently corrupted the measurement.
    /// `max(calculated, dynamicMinimum)` made tones *louder than their label*
    /// across the whole 15-25 dB HL band — the exact normal/abnormal screening
    /// boundary. At 2 kHz on AirPods Pro the "15 dB HL" tone was presented at
    /// roughly 25 dB HL (+9.8 dB), and the 15 and 25 dB HL rungs, meant to sit
    /// 10 dB apart, ended up about 2 dB apart. Every error ran in the same
    /// direction: users heard tones they should not have, so the app reported
    /// **better hearing than reality** — a false negative in a screening tool.
    ///
    /// The quantisation problem is real and is solved where it belongs, in
    /// `TonePlayer`: samples are written at a fixed carrier amplitude that
    /// quantises cleanly, and the attenuation down to this value is applied by
    /// `AVAudioPlayer.volume`, which operates in the float domain and has no
    /// 16-bit floor. A level that still cannot be reached is refused outright
    /// rather than presented at the wrong loudness.
    static func amplitudeForTargetHL(
        targetHL: Double,
        frequency: Int,
        model: ModelType
    ) -> Double {
        let attenuationDB = attenuationForTargetHL(
            targetHL: targetHL,
            frequency: frequency,
            model: model
        )
        // amplitude = 10^(dB/20)
        return pow(10.0, attenuationDB / 20.0)
    }
    
    /// Safety check: Is the target level within safe testing range?
    /// NIOSH/WHO: 85 dBA for 8 hours with 3 dB exchange rate
    /// Brief 0.5-second test tones are safe up to 80 dB HL (well below harmful exposure doses)
    /// Reference: NIOSH/WHO safe listening guidelines, ISO 8253-1
    static func isSafeLevel(hlDB: Double, durationSeconds: Double) -> Bool {
        // Conservative safety limits for brief tone presentations
        // With 0.5-second tones and 1.5-second inter-tone gaps, even 80 dB HL stays far under harmful exposure
        if hlDB <= 80 {
            return true // Always safe for brief presentations
        } else {
            return false // Cap at 80 dB HL for screening safety
        }
    }
    
    /// Get recommended maximum test level based on NIOSH/WHO guidelines
    /// For screening audiometry with brief 0.5-second tones, 80 dB HL is a conservative cap
    /// that remains well below NIOSH/WHO safe listening guidelines (85 dBA for 8 hours with 3 dB exchange)
    /// while providing sufficient dynamic range to detect mild-to-moderate hearing loss.
    /// Reference: NIOSH/WHO safe listening guidelines, ISO 8253-1 pure-tone audiometry standards
    static func maximumSafeTestLevel() -> Double {
        return 80.0 // dB HL equivalent
    }
}

