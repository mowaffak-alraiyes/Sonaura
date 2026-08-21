import Foundation
import Combine
import AVFoundation

/// Hearing Test View Model implementing fast 3-level screening protocol
///
/// **12-Step Fast Screening Protocol:**
///
/// **Frequencies (Hz)**: Sonaura measures pure-tone air-conduction thresholds at 250, 500, 1000, 2000, 4000,
/// and 8000 Hz in each ear. These octave frequencies correspond to the standard adult audiometric test set
/// recommended by ISO 8253-1 and national bodies (BSA, ANSI/ASA), and are commonly used in routine clinical
/// audiograms.
///
/// **4-Level Screening Ladder**: Each step uses a silent 4-level check at clinically-justified levels:
/// - **15 dB HL**: Excellent hearing range (distinguishes excellent from normal hearing)
/// - **25 dB HL**: Upper limit of normal / subclinical loss
/// - **40 dB HL**: Boundary of mild vs moderate loss
/// - **55 dB HL**: Upper moderate region
/// - If not heard at all levels: ≥55 dB HL (likely moderately severe or worse)
///
/// **Procedure**: For each ear–frequency pair:
/// 1. Play tone at 15 dB HL → if YES, store "≤15 dB HL" (excellent hearing, approximate threshold: 7.5 dB HL) and advance
/// 2. If NO, play tone at 25 dB HL → if YES, store "15-25 dB HL" (normal hearing, approximate threshold: 20 dB HL) and advance
/// 3. If NO, play tone at 40 dB HL → if YES, store "25-40 dB HL" (mild loss, approximate threshold: 32.5 dB HL) and advance
/// 4. If NO, play tone at 55 dB HL → if YES, store "40-55 dB HL" (moderate loss, approximate threshold: 47.5 dB HL) and advance
/// 5. If NO to all → store "≥55 dB HL" (moderately severe or worse, approximate threshold: 70 dB HL) and advance
///
/// Each step takes ≤3 seconds for excellent-hearing users and ≤8 seconds for moderate-loss users.
/// The user never knows there are multiple levels being tested—they just answer yes/no up to 4 times per step.
///
/// **Alternating Ears**: Order: R 1000, L 1000, R 2000, L 2000, R 4000, L 4000, R 8000, L 8000, R 500, L 500, R 250, L 250.
/// This preserves symmetry, reduces fatigue bias, and follows the recommended audiometric frequency order.
///
/// **ISO 7029 Integration**: Approximate thresholds (20, 35, 50, 60 dB HL) are fed into ISO 7029 model using
/// user age/sex to compute percentiles, producing age-adjusted hearing comparisons.
///
/// **References**:
/// - ISO 8253-1: Acoustics — Audiometric test methods — Part 1: Pure-tone air and bone conduction audiometry
/// - ISO 7029:2017: Statistical distribution of hearing thresholds related to age
/// - BSA: British Society of Audiology pure-tone procedure
/// - ANSI/ASA S3.6-2018: Specification for Audiometers
@MainActor
final class HearingTestViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isRunning: Bool = false
    @Published var currentStepIndex: Int = 0
    @Published var steps: [HearingTestStep] = []
    @Published var completedResults: [ThresholdResult] = []
    @Published var testSession: HearingTestSession?
    
    // Hardware monitors - injected by coordinator
    @Published var routeMonitor: AudioRouteMonitor!
    @Published var bluetooth: BluetoothAccessManager!
    @Published var volume: VolumeMonitor!
    @Published var noiseMonitor: AmbientNoiseMonitor!
    
    // Coordinator reference for audio session management
    private weak var coordinator: HearingTestCoordinator?

    /// Stable identity for rate limiting, for the lifetime of the install.
    ///
    /// Persisted rather than regenerated so the limit actually accumulates
    /// across calls. Not a user identity and not used for anything else; when
    /// real accounts exist, swap this for the account id.
    static let rateLimitIdentity: String = {
        let key = "com.sonaura.rateLimitIdentity"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = "install_\(UUID().uuidString)"
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }()
    
    /// Inject monitors from coordinator (called during coordinator initialization)
    func injectMonitors(
        routeMonitor: AudioRouteMonitor,
        bluetooth: BluetoothAccessManager,
        volume: VolumeMonitor,
        noiseMonitor: AmbientNoiseMonitor
    ) {
        self.routeMonitor = routeMonitor
        self.bluetooth = bluetooth
        self.volume = volume
        self.noiseMonitor = noiseMonitor
    }
    
    /// Set coordinator reference (called during coordinator initialization)
    func setCoordinator(_ coordinator: HearingTestCoordinator) {
        self.coordinator = coordinator
    }
    
    // User configuration
    @Published var userAge: Int?
    @Published var userGender: ISO7029Calculator.Gender = .male
    @Published var airPodsModel: AirPodsCalibration.ModelType = .airPodsPro
    @Published var includeExtendedHigh: Bool = false // Include 12 kHz
    
    // Current test state
    @Published var currentPresentationLevel: Double = 25.0 // Current dB HL being tested
    @Published var currentInstructions: String = ""
    @Published var isWaitingForResponse: Bool = false
    @Published var hasPlayedCurrentTone: Bool = false // Track if tone has been played for current level
    
    private var testStartTime: Date?
    
    // Audio
    private let tonePlayer = TonePlayer()
    
    // Test configuration
    /// Tone duration: 0.5 seconds per presentation (clinical standard for pure-tone audiometry)
    /// Inter-tone gap: 1.0-1.5 seconds (recommended to prevent fatigue and allow clear responses)
    /// Reference: ISO 8253-1, BSA pure-tone procedure guidelines
    private let toneDuration: TimeInterval = 0.5 // 0.5 seconds per tone
    private let interToneGap: TimeInterval = 1.0 // 1.0-1.5 seconds between tones
    
    // 4-level screening ladder: clinically-justified levels
    // 15 dB HL → excellent hearing range (distinguishes excellent from normal)
    // 25 dB HL → upper limit of normal / subclinical loss
    // 40 dB HL → boundary of mild vs moderate loss
    // 55 dB HL → upper moderate region
    // If not heard → likely ≥moderately severe
    private let screeningLevels: [Double] = [15.0, 25.0, 40.0, 55.0]
    
    // Current state for 4-level ladder
    private var currentLevelIndex: Int = 0 // Which level in the ladder (0, 1, 2, or 3)
    private var currentStepPresentations: [TonePresentation] = []
    
    // MARK: - Test Frequencies & Sequencing
    
    /// Standard audiometric frequencies matching ISO 8253-1 and BSA recommendations
    /// Frequencies: 250, 500, 1000, 2000, 4000, 8000 Hz
    /// These correspond to the standard adult pure-tone audiometric test set recommended by
    /// ISO 8253-1 and national bodies (BSA, ANSI/ASA), commonly used in routine clinical audiograms.
    /// They span the low-, mid-, and high-frequency regions most relevant for speech audibility
    /// and noise-induced hearing loss detection.
    /// Reference: ISO 8253-1, BSA pure-tone procedure, ANSI/ASA S3.6-2018
    private var testFrequencies: [Int] {
        // Standard 6 frequencies per ear (12 total steps)
        let standardFreqs = [1000, 2000, 4000, 8000, 500, 250]
        
        // Optional extended high frequency (12 kHz) if enabled
        if includeExtendedHigh {
            return standardFreqs + [12000]
        }
        return standardFreqs
    }
    
    // MARK: - Computed Properties
    
    var currentStep: HearingTestStep? {
        guard isRunning, currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }
    
    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        return Double(currentStepIndex) / Double(steps.count)
    }
    
    var canStartHardware: Bool {
        guard routeMonitor.isHeadphoneLikeConnected else { return false }
        switch routeMonitor.currentRoute {
        case .bluetooth, .airPods:
            return bluetooth.isReady
        case .wiredHeadphones:
            return true
        case .builtInSpeaker, .other:
            return false
        }
    }
    
    var isAtMaxVolume: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return volume.outputVolume >= 0.99  // Require 99% or higher for "maximum"
        #endif
    }
    
    var canStart: Bool {
        return canStartHardware && isAtMaxVolume && noiseMonitor.isQuietEnough
    }
    
    // MARK: - Test Control
    
    /// Start a new hearing test with rate limiting and input validation
    /// OWASP: Rate limit user actions to prevent abuse
    func startTest() {
        // BYPASSED FOR TESTING - normally: guard canStart else { return }
        
        // OWASP: Rate limiting - prevent abuse of test start action
        Task { @MainActor in
            do {
                // Check rate limit before starting test
                // Stable per-install identity; a fresh UUID per call meant
                // the rate limit could never be reached. See `rateLimitIdentity`.
                let userIdentifier = Self.rateLimitIdentity
                _ = try await AppRateLimiter.checkLimit(
                    action: "test_start",
                    identifier: userIdentifier,
                    config: .testStart
                )
                
                // Validate user inputs before starting
                if let age = userAge {
                    _ = try SecurityValidator.validateAge(age)
                }
                
                // Proceed with test start
                await performTestStart()
                
            } catch let error as SecurityValidationError {
                // Handle rate limit or validation errors gracefully
                print("⚠️ Security validation failed: \(error.localizedDescription)")
                currentInstructions = "Please wait a moment before starting another test."
                // Don't start test if validation fails
                return
            } catch {
                print("❌ Unexpected error: \(error)")
                return
            }
        }
    }
    
    /// Internal method to perform actual test start (separated for rate limiting)
    @MainActor
    private func performTestStart() async {
        testStartTime = Date()
        currentStepIndex = 0
        completedResults.removeAll()
        currentStepPresentations.removeAll()
        
        // Pre-configure audio session for faster response
        // Switch to playback mode immediately so tones play instantly when button is pressed
        if let coordinator = coordinator {
            await coordinator.beginTonePlaybackSession()
        }
        
        // Generate test sequence
        steps = makeSteps()
        
        isRunning = true
        // Start first step automatically
        startCurrentStep()
    }
    
    func nextStep() {
        // Not used in 3-level protocol - steps advance automatically
        // This method kept for backward compatibility but does nothing
    }
    
    /// Start the current step with 3-level screening protocol
    /// User must press "Play Sound" button to hear the tone
    private func startCurrentStep() {
        guard let step = currentStep else {
            completeTest()
            return
        }
        
        // Reset for new step
        currentLevelIndex = 0
        currentStepPresentations.removeAll()
        hasPlayedCurrentTone = false
        
        // Update UI - wait for user to press "Play Sound"
        currentInstructions = "Press 'Play Sound' to hear the tone"
        currentPresentationLevel = screeningLevels[0] // Start at 15 dB HL
        isWaitingForResponse = false // Don't wait until tone is played
    }
    
    /// User-initiated tone playback (called when "Play Sound" button is pressed)
    func playSound() {
        // Only allow playing if we're not currently waiting for a response
        // (i.e., tone hasn't been played yet, or user already responded and we're on next level)
        guard !isWaitingForResponse else {
            print("⚠️ Cannot play sound: already waiting for response")
            return
        }
        
        // Update UI immediately for instant feedback
        currentInstructions = "Did you hear that beep?"
        
        print("🔊 Playing sound at level \(currentLevelIndex): \(screeningLevels[currentLevelIndex]) dB HL")
        
        // Play tone immediately - no blocking checks
        playCurrentTone()
    }
    
    func restart() {
        // Restore the audio session on the abandon path too.
        //
        // Teardown used to run after every single tone, so an abandoned test
        // happened to get cleaned up by the last one. Now that
        // `beginTonePlaybackSession()` is correctly paired with exactly one
        // `endTonePlaybackSession()` at the end of a *completed* test, backing
        // out mid-test would otherwise leave the session in playback mode with
        // the noise monitor stopped.
        Task { @MainActor in
            if let coordinator = coordinator {
                await coordinator.endTonePlaybackSession()
            }
        }

        isRunning = false
        currentStepIndex = 0
        completedResults.removeAll()
        currentStepPresentations.removeAll()
        steps.removeAll()
        testSession = nil
        isWaitingForResponse = false
        hasPlayedCurrentTone = false
        currentLevelIndex = 0
        tonePlayer.stop()
    }
    
    /// Generate test steps with alternating ear order per frequency
    /// Order: R 1000, L 1000, R 2000, L 2000, R 4000, L 4000, R 8000, L 8000, R 500, L 500, R 250, L 250
    /// This preserves symmetry, reduces fatigue bias towards the first-tested ear, and follows
    /// the recommended audiometric frequency order (1k → 2k → 4k → 8k → 500 → 250 Hz).
    /// Reference: BSA pure-tone procedure, Interacoustics clinical guidelines
    private func makeSteps() -> [HearingTestStep] {
        var allSteps: [HearingTestStep] = []
        var sequenceNum = 0
        
        // Alternate between right and left ear for each frequency
        // This matches BSA recommended order while preventing one ear from being fatigued first
        for freq in testFrequencies {
            // Right ear first for this frequency
            allSteps.append(HearingTestStep(
                frequencyHz: freq,
                ear: .right,
                sequenceNumber: sequenceNum
            ))
            sequenceNum += 1
            
            // Then left ear for the same frequency
            allSteps.append(HearingTestStep(
                frequencyHz: freq,
                ear: .left,
                sequenceNumber: sequenceNum
            ))
            sequenceNum += 1
        }
        
        return allSteps
    }
    
    // MARK: - 4-Level Screening Protocol
    
    /// Play the current tone at the current level in the ladder
    private func playCurrentTone() {
        guard let step = currentStep else { return }
        
        let level = screeningLevels[currentLevelIndex]
        currentPresentationLevel = level
        
        // CRITICAL: Verify system volume is at maximum.
        //
        // This is a hard gate, not a warning. The whole calibration chain in
        // `AirPodsCalibration` is derived from a max-SPL figure that assumes
        // output at 100%; at any lower volume every presented level is
        // attenuated by an unknown amount and the resulting dB HL numbers are
        // meaningless. This used to only set an instruction string and then
        // fall through and play the tone anyway, so a user at 50% volume could
        // complete an entire test and be handed an audiogram — with nothing in
        // the exported PDF indicating the result was invalid.
        //
        // iOS cannot *set* system volume from an app, but it can decline to
        // measure until the user does.
        let systemVolume = volume?.outputVolume ?? 0.0
        guard systemVolume >= 0.95 else {
            print("⛔️ BLOCKED: System volume is \(Int(systemVolume * 100))% - 100% is required for a valid measurement")
            currentInstructions = "Set your iPhone volume to 100%, then tap Play Sound again. Results are only valid at full volume."
            hasPlayedCurrentTone = false
            isWaitingForResponse = false
            return
        }

        // Spatial audio re-renders both channels and defeats the per-ear
        // isolation this whole measurement rests on. See
        // `AudioRouteMonitor.isSpatialAudioActive`.
        if routeMonitor?.isSpatialAudioActive == true {
            print("⛔️ BLOCKED: Spatial Audio is active - per-ear isolation is not possible")
            currentInstructions = "Turn off Spatial Audio for your headphones (Settings › Bluetooth › ⓘ › Spatial Audio › Off), then tap Play Sound again."
            hasPlayedCurrentTone = false
            isWaitingForResponse = false
            return
        }
        
        // Play tone immediately - audio session is already configured
        // No delays or async waits for instant response
        let earName = step.ear == .left ? "LEFT" : (step.ear == .right ? "RIGHT" : "BOTH")
        
        // Comprehensive logging for debugging
        print("═══════════════════════════════════════════")
        print("🔊 TONE PLAYBACK DEBUG")
        print("═══════════════════════════════════════════")
        print("   Step: \(currentStepIndex + 1)/\(steps.count)")
        print("   Level Index: \(currentLevelIndex)/\(screeningLevels.count - 1)")
        print("   Frequency: \(step.frequencyHz) Hz")
        print("   Ear: \(earName)")
        print("   Target Level: \(level) dB HL")
        print("   System Volume: \(Int(systemVolume * 100))%")
        
        let amplitude = amplitudeForTone(frequency: step.frequencyHz, levelDB: level)
        let earChannel = self.earChannel(for: step.ear)
        let splLevel = AirPodsCalibration.convertHLtoSPL(hlDB: level, frequency: step.frequencyHz)
        let maxSPL = airPodsModel.maxOutputSPL(at: step.frequencyHz)
        let attenuationDB = AirPodsCalibration.attenuationForTargetHL(
            targetHL: level,
            frequency: step.frequencyHz,
            model: airPodsModel
        )
        
        print("   Target SPL: \(String(format: "%.1f", splLevel)) dB SPL")
        print("   Max Output SPL: \(String(format: "%.1f", maxSPL)) dB SPL")
        print("   Attenuation: \(String(format: "%.1f", attenuationDB)) dB")
        print("   Calculated Amplitude: \(String(format: "%.6f", Double(amplitude)))")
        print("   Final Amplitude (clamped): \(String(format: "%.6f", Double(amplitude)))")
        
        // Verify amplitude is audible (not zero or near-zero)
        if amplitude < 0.0001 {
            print("   ❌ ERROR: Amplitude too low - tone may be inaudible!")
        } else if amplitude < 0.001 {
            print("   ⚠️ WARNING: Amplitude very low - tone may be barely audible")
        } else {
            print("   ✅ Amplitude OK - tone should be audible")
        }
        
        print("   Ear Channel: \(earChannel)")
        print("   Duration: \(toneDuration)s")
        print("═══════════════════════════════════════════")
        
        // Play tone immediately - no delays, no async waits
        let didPlay = tonePlayer.playTone(
            frequency: Double(step.frequencyHz),
            duration: toneDuration,
            ear: earChannel,
            level: amplitude
        )

        // A refused presentation must not be scored. `playTone` returns false
        // when the requested level is unreachable on this hardware; treating
        // that as "played, and not heard" would record a threshold the test
        // never actually measured.
        guard didPlay else {
            currentInstructions = "This level can't be produced on your headphones. Tap Skip to continue."
            hasPlayedCurrentTone = false
            isWaitingForResponse = false
            return
        }

        hasPlayedCurrentTone = true
        isWaitingForResponse = true

        // NOTE: the session teardown that used to live here was removed.
        // `beginTonePlaybackSession()` is called once per test, but this ran
        // after *every* tone and also restarted the mic monitor, which forces
        // HFP mono on Bluetooth headphones — exactly the routing the begin call
        // exists to avoid. Only the first tone of a test was getting stereo
        // A2DP. Teardown now happens once, when the test ends.
    }
    
    /// Record user response and handle 4-level ladder progression
    /// OWASP: Rate limit responses to prevent automated abuse
    func recordResponse(heard: Bool) {
        guard let step = currentStep,
              hasPlayedCurrentTone,
              isWaitingForResponse else {
            // If tone hasn't been played yet, ignore response
            return
        }

        // Close the window before suspending.
        //
        // The guard above is checked synchronously, but the work below hops
        // through `Task { @MainActor }` and awaits an actor-isolated rate-limit
        // check before `performResponseRecording` clears `isWaitingForResponse`.
        // Two taps landing inside that gap both passed the guard, so a single
        // presentation was recorded twice — the second append using an
        // already-advanced `currentLevelIndex` against a stale `step`, which
        // corrupts `currentStepPresentations` and can skip a level outright.
        // Clearing here makes the guard mean what it looks like it means.
        isWaitingForResponse = false

        // OWASP: Rate limiting for test responses (prevents automated responses)
        Task { @MainActor in
            do {
                // A stable per-install identifier. This was
                // `"user_\(UUID().uuidString)"`, freshly generated on every
                // call, so the rate-limit key was unique each time and the
                // limit could never be reached — while `RateLimiter.requestHistory`
                // gained a permanent entry per call that `cleanup()` never
                // removed, leaking for the life of the process. SECURITY.md
                // describes rate limiting as an implemented control; with a
                // random key it was decorative.
                let userIdentifier = Self.rateLimitIdentity
                _ = try await AppRateLimiter.checkLimit(
                    action: "test_response",
                    identifier: userIdentifier,
                    config: .testResponse
                )
                
                // Proceed with response recording
                await performResponseRecording(heard: heard, step: step)
                
            } catch let error as SecurityValidationError {
                print("⚠️ Rate limit exceeded: \(error.localizedDescription)")
                // Don't process response if rate limited
                return
            } catch {
                print("❌ Unexpected error: \(error)")
                return
            }
        }
    }
    
    /// Internal method to perform response recording (separated for rate limiting)
    @MainActor
    private func performResponseRecording(heard: Bool, step: HearingTestStep) async {
        isWaitingForResponse = false
        
        let currentLevel = screeningLevels[currentLevelIndex]
        
        // Record this presentation
        let presentation = TonePresentation(
            frequencyHz: step.frequencyHz,
            ear: step.ear,
            levelDB: currentLevel,
            heard: heard
        )
        currentStepPresentations.append(presentation)
        
        if heard {
            // User heard the tone - determine category and move to next step
            let category: ThresholdCategory
            switch currentLevelIndex {
            case 0: // Heard at 15 dB HL
                category = .excellentHearing // ≤15 dB HL
            case 1: // Heard at 25 dB HL
                category = .normalHearing // 15-25 dB HL
            case 2: // Heard at 40 dB HL
                category = .mildLoss // 25-40 dB HL
            case 3: // Heard at 55 dB HL
                category = .moderateLoss // 40-55 dB HL
            default:
                category = .moderateLoss // Fallback
            }
            
            // Store result
            let thresholdResult = ThresholdResult(
                frequencyHz: step.frequencyHz,
                ear: step.ear,
                category: category,
                presentations: currentStepPresentations
            )
            completedResults.append(thresholdResult)
            
            // Move to next step
            advanceToNextStep()
            
        } else {
            // User didn't hear - try next level if available
            if currentLevelIndex < screeningLevels.count - 1 {
                // Move to next level
                currentLevelIndex += 1
                hasPlayedCurrentTone = false
                
                // Update UI to wait for user to press "Play Sound" again
                let nextLevel = screeningLevels[currentLevelIndex]
                let previousLevel = screeningLevels[currentLevelIndex - 1]
                currentInstructions = "Volume increased to \(Int(nextLevel)) dB HL. Press 'Play Sound' to hear the next tone"
                currentPresentationLevel = nextLevel // Update presentation level
                isWaitingForResponse = false
                // Don't auto-play - wait for user to press button
            } else {
                // All levels exhausted - threshold ≥55 dB HL
                let category = ThresholdCategory.moderateSevereOrWorse // ≥55 dB HL
                
                let thresholdResult = ThresholdResult(
                    frequencyHz: step.frequencyHz,
                    ear: step.ear,
                    category: category,
                    presentations: currentStepPresentations
                )
                completedResults.append(thresholdResult)
                
                // Move to next step
                advanceToNextStep()
            }
        }
    }
    
    private func advanceToNextStep() {
        currentStepIndex += 1
        
        if currentStepIndex >= steps.count {
            completeTest()
        } else {
            startCurrentStep()
        }
    }
    
    private func completeTest() {
        // Ensure we have results before creating session
        guard !completedResults.isEmpty else {
            print("⚠️ No results to save - test may have completed without collecting data")
            isRunning = false
            return
        }
        
        print("✅ Test complete: \(completedResults.count) results collected")
        
        // Restore audio session to playAndRecord for monitoring (non-blocking)
        Task { @MainActor in
            if let coordinator = coordinator {
                await coordinator.endTonePlaybackSession()
            }
        }
        
        // Create test session
        let startTime = testStartTime ?? Date() // Use current time if startTime wasn't set
        
        // Update state (already on main thread since class is @MainActor)
        isRunning = false
        isWaitingForResponse = false
        
        testSession = HearingTestSession(
            results: completedResults,
            startTime: startTime,
            endTime: Date(),
            deviceModel: airPodsModel.rawValue,
            userAge: userAge,
            userGender: userGender
        )
        
        tonePlayer.stop()
        
        print("✅ Test session created: \(testSession != nil) with \(completedResults.count) results")
    }
    
    // MARK: - Results Summary
    
    func summaryByEar() -> [(ear: TestEar, thresholds: [Int: Double], pta: Double?, classification: HearingClassification)] {
        guard let session = testSession else { return [] }
        
        var summary: [(TestEar, [Int: Double], Double?, HearingClassification)] = []
        
        for ear in [TestEar.right, TestEar.left] {
            let earResults = session.results(for: ear)
            let thresholds = Dictionary(uniqueKeysWithValues: earResults.map { ($0.frequencyHz, $0.thresholdDB) })
            let pta = session.pureToneAverage(ear: ear)
            let classification = session.overallClassification(ear: ear)
            
            summary.append((ear, thresholds, pta, classification))
        }
        
        return summary
    }
    
    /// Get percentile for a specific result compared to age-matched norms
    func percentileForResult(_ result: ThresholdResult) -> Double? {
        guard let age = userAge else { return nil }
        
        return ISO7029Calculator.percentile(
            measuredThreshold: result.thresholdDB,
            age: age,
            frequency: result.frequencyHz,
            gender: userGender
        )
    }
    
    /// Get expected median for user's age
    func expectedMedianForFrequency(_ frequency: Int) -> Double {
        let age = userAge ?? 25 // Default to 25 if not provided
        return ISO7029Calculator.medianThreshold(
            age: age,
            frequency: frequency,
            gender: userGender
        )
    }
    
    private func amplitudeForTone(frequency: Int, levelDB: Double) -> Float {
        let amplitude = AirPodsCalibration.amplitudeForTargetHL(
            targetHL: levelDB,
            frequency: frequency,
            model: airPodsModel
        )
        
        // Clamp to valid range (AirPodsCalibration already applies minimum, but ensure max)
        let safeAmplitude = max(0.0, min(1.0, Float(amplitude)))
        
        return safeAmplitude
    }
    
    private func earChannel(for ear: TestEar) -> EarChannel {
        switch ear {
        case .left:
            return .left
        case .right:
            return .right
        case .both:
            return .both
        }
    }
}
