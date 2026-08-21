import Foundation

/// Implements the Hughson-Westlake staircase method for hearing threshold detection.
///
/// Clinical standard: **10 dB down on a response, 5 dB up on no response.**
/// Threshold is the lowest level with 2-of-3 (or 3-of-5) ascending responses.
///
/// > ⚠️ **NOT CURRENTLY USED.** Nothing in the app instantiates this type. The
/// > shipping test is the fixed 4-rung ladder in
/// > `HearingTestViewModel.advanceLadder` (15/25/40/55 dB HL, single
/// > presentation per rung), which is a category screen, not a threshold
/// > search. `IMPLEMENTATION_SUMMARY.md` previously described Hughson-Westlake
/// > as the app's method; that was never true of the running code.
/// >
/// > Kept because a real threshold search is the right long-term direction and
/// > this is most of one. The step directions were inverted and have been
/// > corrected, but **this code has never run** — treat it as unverified and
/// > cover it with tests before wiring it to anything.
final class StaircaseController {
    
    enum StaircaseRule {
        case twoOfThree  // 2 ascending responses out of 3 attempts
        case threeOfFive // 3 ascending responses out of 5 attempts (more reliable)
    }
    
    private let rule: StaircaseRule
    private let startingLevelDB: Double
    private let maxLevelDB: Double // Safety ceiling
    private let minLevelDB: Double
    
    // State tracking
    private(set) var currentLevelDB: Double
    private var isAscending: Bool = false
    private var descendingStarted: Bool = false
    private var ascendingResponses: [(level: Double, heard: Bool)] = []
    private var levelAttempts: [Double: Int] = [:] // Count attempts at each level
    
    /// Initialize a new staircase for one frequency/ear combination
    /// Uses modified Hughson-Westlake procedure: 10 dB down on "heard", 5 dB up on "not heard"
    /// Threshold determined when 2-of-3 ascending responses occur at same level
    /// - Parameters:
    ///   - startingLevelDB: Initial presentation level (typically user's 1 kHz threshold + 20 dB)
    ///   - maxLevelDB: Safety ceiling (80 dB HL equivalent for screening, well below NIOSH/WHO limits)
    ///   - minLevelDB: Floor level (0 dB HL equivalent minimum)
    ///   - rule: Detection rule (default: 2-of-3 ascending responses)
    /// Reference: ISO 8253-1, BSA pure-tone procedure, Hughson-Westlake method
    init(startingLevelDB: Double = 35.0,
         maxLevelDB: Double = 80.0,
         minLevelDB: Double = 0.0,
         rule: StaircaseRule = .twoOfThree) {
        self.startingLevelDB = startingLevelDB
        self.maxLevelDB = maxLevelDB
        self.minLevelDB = minLevelDB
        self.currentLevelDB = startingLevelDB
        self.rule = rule
    }
    
    /// Record a response and update the staircase state
    /// - Parameter heard: true if user heard the tone, false if not
    /// - Returns: StaircaseResult with next action (continue, threshold found, or error)
    func recordResponse(heard: Bool) -> StaircaseResult {
        
        // Descending phase: decrease by 10 dB until first "not heard"
        // Modified Hughson-Westlake: 10 dB down on "heard", then switch to ascending phase
        if !descendingStarted {
            if heard {
                currentLevelDB -= 10.0
                if currentLevelDB < minLevelDB {
                    // Clamp to minimum rather than error (threshold may be very sensitive)
                    currentLevelDB = minLevelDB
                    descendingStarted = true
                    isAscending = true
                    print("🔊 Descending reached minimum, starting ascent: \(currentLevelDB) dB HL")
                    return .continueTest(nextLevelDB: currentLevelDB)
                }
                print("🔊 Descending: \(currentLevelDB) dB HL")
                return .continueTest(nextLevelDB: currentLevelDB)
            } else {
                // First "not heard" - begin ascending phase
                descendingStarted = true
                isAscending = true
                currentLevelDB += 5.0
                if currentLevelDB > maxLevelDB {
                    // If we hit max level and still no response, threshold exceeds screening limit
                    return .error("Threshold exceeds maximum safe screening level (\(maxLevelDB) dB HL). Recommend full audiology evaluation.")
                }
                print("🔊 Starting ascent: \(currentLevelDB) dB HL")
                return .continueTest(nextLevelDB: currentLevelDB)
            }
        }
        
        // Hughson-Westlake proper: **down 10 dB on heard, up 5 dB on not-heard.**
        //
        // This was inverted — `+5` on heard and `-10` on not heard — which is
        // not a slower convergence, it is divergence in both directions: hear
        // the tone and it gets louder so you keep hearing it, all the way to
        // the ceiling; miss it and it gets quieter so you keep missing it, all
        // the way to the floor. It could never bracket a threshold. The
        // comment on the old `else` branch stated the rule backwards too, and
        // the file header still contradicted the initialiser's doc comment.
        ascendingResponses.append((level: currentLevelDB, heard: heard))

        if heard {
            // A response at this level. Check the 2-of-3 (or 3-of-5) criterion
            // before stepping down, since the criterion is evaluated on the
            // level that was just responded to.
            if let threshold = checkThresholdCriterion() {
                print("🎯 Threshold found: \(threshold) dB HL")
                return .thresholdFound(thresholdDB: threshold)
            }

            // Heard it: go down 10 dB and look for the quietest level that
            // still gets a response.
            currentLevelDB -= 10.0
            if currentLevelDB < minLevelDB {
                // Already at the floor and still audible: the threshold is at
                // or below the quietest level this screen can present.
                currentLevelDB = minLevelDB
                return .thresholdFound(thresholdDB: minLevelDB)
            }
            print("🔊 Descending: \(currentLevelDB) dB HL")
        } else {
            // Missed it: go up 5 dB. The finer ascending step is what sets the
            // resolution of the final threshold.
            currentLevelDB += 5.0
            if currentLevelDB > maxLevelDB {
                // Hit the safety ceiling with no response.
                if let bestEstimate = estimateThresholdFromResponses() {
                    return .thresholdFound(thresholdDB: min(bestEstimate, maxLevelDB))
                }
                return .error("Unable to determine threshold at safe screening levels (max \(maxLevelDB) dB HL). Strongly recommend full audiology evaluation.")
            }
            print("🔊 Ascending: \(currentLevelDB) dB HL")
        }
        
        // Safety: prevent infinite loops (max 20 presentations)
        if ascendingResponses.count > 20 {
            if let bestEstimate = estimateThresholdFromResponses() {
                return .thresholdFound(thresholdDB: bestEstimate)
            }
            return .error("Test exceeded maximum attempts")
        }
        
        return .continueTest(nextLevelDB: currentLevelDB)
    }
    
    /// Check if the threshold criterion is met (2-of-3 or 3-of-5 at same level)
    private func checkThresholdCriterion() -> Double? {
        let heardResponses = ascendingResponses.filter { $0.heard }
        
        // Group heard responses by level (allowing ±2.5 dB tolerance for rounding)
        let levelCounts = Dictionary(grouping: heardResponses) { response in
            (response.level / 5.0).rounded() * 5.0
        }
        
        switch rule {
        case .twoOfThree:
            // Need 2 ascending "heard" responses at the same level
            for (level, responses) in levelCounts {
                if responses.count >= 2 {
                    return level
                }
            }
            
        case .threeOfFive:
            // Need 3 ascending "heard" responses at the same level
            for (level, responses) in levelCounts {
                if responses.count >= 3 {
                    return level
                }
            }
        }
        
        return nil
    }
    
    /// Estimate threshold from response pattern if criterion not perfectly met
    private func estimateThresholdFromResponses() -> Double? {
        let heardResponses = ascendingResponses.filter { $0.heard }
        guard !heardResponses.isEmpty else { return nil }
        
        // Use the lowest level at which tone was heard (conservative estimate)
        return heardResponses.map { $0.level }.min()
    }
    
    enum StaircaseResult: Equatable {
        case continueTest(nextLevelDB: Double)
        case thresholdFound(thresholdDB: Double)
        case error(String)
    }
}

