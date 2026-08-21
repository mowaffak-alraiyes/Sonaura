import Foundation
import AVFoundation

/// Simple sine-wave tone generator using AVAudioEngine + AVAudioSourceNode.
/// Supports equal-power panning for left/right ear presentation and a short attack/release envelope to avoid clicks.
final class ToneGenerator {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
    private var mixerNode: AVAudioMixerNode!  // Use mixer node for pan control
    // Use shared audio session instead of creating our own
    // The coordinator manages the session configuration
    private let session = AVAudioSession.sharedInstance()

    // Realtime state accessed in render block (avoid locks/allocations there).
    // Small benign data races on these Doubles are acceptable for MVP audio.
    private var sampleRate: Double = 44100
    private var phase: Double = 0
    private var frequency: Double = 1000
    private var amplitude: Double = 0.2 // 0.0 - 1.0 (keep conservative for safety)
    private var pan: Double = 0.0       // -1.0 = left, 0 = center, +1.0 = right
    private var useHardPanning: Bool = true  // Use hard panning (complete channel muting) for hearing tests

    // Gating/envelope for one-shot playback
    private var playing: Bool = false
    private var framesRemaining: Int = 0
    private var attackFrames: Int = 0
    private var releaseFrames: Int = 0
    private var totalFramesForThisTone: Int = 0
    private var hasLoggedPanInfo: Bool = false // Track if we've logged pan info for current tone

    init() {
        // Don't configure session here - coordinator handles it
        // Just setup the engine
        setupEngine()
    }

    private func setupEngine() {
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outFormat.sampleRate
        
        // Force stereo output format for proper left/right ear routing
        // Create a stereo format if output is mono
        let stereoFormat: AVAudioFormat
        if outFormat.channelCount < 2 {
            // Output is mono, create stereo format
            stereoFormat = AVAudioFormat(standardFormatWithSampleRate: outFormat.sampleRate, channels: 2) ?? outFormat
            print("⚠️ ToneGenerator: Output is mono, creating stereo format")
        } else {
            stereoFormat = outFormat
        }
        
        print("🎧 ToneGenerator: Output format - \(stereoFormat.channelCount) channels, \(stereoFormat.sampleRate) Hz")
        
        // Verify channel layout for debugging
        if let channelLayout = stereoFormat.channelLayout {
            print("🎧 Channel layout tag: \(channelLayout.layoutTag)")
        } else {
            print("⚠️ No channel layout specified - using default stereo mapping (Channel 0=Left, Channel 1=Right)")
        }

        // Verify audio session output channels
        let sessionChannels = session.outputNumberOfChannels
        print("🎧 Audio session output channels: \(sessionChannels)")
        if sessionChannels < 2 {
            print("❌ CRITICAL: Audio session is MONO! Tones will play in both ears.")
            print("   Fix: Ensure audio session is configured for stereo output")
            print("   Check: iPhone Settings → Accessibility → Audio/Visual → Mono Audio (should be OFF)")
        } else {
            print("✅ Audio session is STEREO - channel isolation should work correctly")
        }

        sourceNode = AVAudioSourceNode(format: stereoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let channels = Int(abl.count)
            let frames = Int(frameCount)

            if channels == 0 { return noErr }

            // Hard panning for hearing tests - completely mute one channel
            // This ensures complete isolation between ears (clinical requirement)
            let clampedPan = max(-1.0, min(1.0, self.pan))
            let leftGain: Double
            let rightGain: Double
            
            if clampedPan <= -0.99 {
                // Hard left - completely mute right channel
                leftGain = 1.0
                rightGain = 0.0
            } else if clampedPan >= 0.99 {
                // Hard right - completely mute left channel
                leftGain = 0.0
                rightGain = 1.0
            } else {
                // Center or slight pan - use equal-power panning
                let angle = (clampedPan + 1.0) * .pi / 4.0
                leftGain = cos(angle)
                rightGain = sin(angle)
            }

            // Local copies for speed
            var localPhase = self.phase
            let localFreq = self.frequency
            let sr = self.sampleRate
            let twoPi = 2.0 * Double.pi

            // Envelope counters
            var localFramesRemaining = self.framesRemaining
            let attack = max(1, self.attackFrames)
            let release = max(1, self.releaseFrames)
            let total = max(1, self.totalFramesForThisTone)
            let sustainStart = attack
            let releaseStart = max(attack, total - release)

            // Clear output first
            for b in 0..<channels {
                memset(abl[b].mData, 0, Int(abl[b].mDataByteSize))
            }

            guard self.playing, localFramesRemaining > 0 else {
                // Not playing, keep buffers zeroed
                return noErr
            }

            // Fill audio
            for frame in 0..<frames {
                if localFramesRemaining <= 0 {
                    break
                }

                // Calculate envelope (attack -> sustain -> release)
                let framesPlayed = total - localFramesRemaining
                let env: Double
                if framesPlayed < sustainStart {
                    // Attack
                    env = Double(framesPlayed) / Double(attack)
                } else if framesPlayed >= releaseStart {
                    // Release
                    let relFrames = framesPlayed - releaseStart
                    env = max(0.0, 1.0 - Double(relFrames) / Double(release))
                } else {
                    // Sustain
                    env = 1.0
                }

                let phaseInc = twoPi * localFreq / sr
                let sample = sin(localPhase) * self.amplitude * env

                // Write to channels (support mono or stereo)
                if channels == 1 {
                    // Mono output - can't pan, so play in center
                    let ptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = Float(sample)
                    // No logging here: this is the real-time render thread.
                    // The mono-output condition is already reported once at
                    // setup (see the session-channel check in `configure`),
                    // which is off this thread and just as visible.
                } else if channels >= 2 {
                    // Hard panning for hearing tests - completely mute one channel
                    // We write directly to channels AND use mixer pan for double protection
                    let lptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
                    let rptr = abl[1].mData!.assumingMemoryBound(to: Float.self)
                    
                    // Branch on the requested pan, not on the computed gains.
                    //
                    // The gains cannot distinguish centre from hard-left: the
                    // equal-power law gives leftGain == rightGain == 0.707 at
                    // pan 0, which satisfied `leftGain > 0.001` and took the
                    // hard-left branch, explicitly zeroing the right channel.
                    // So `.both` — `setPanForEar(.both)`, `playCalibrated(ear: .both)`
                    // and the default argument of `play(frequency:)` — played
                    // in the left ear only, at 0.707 gain.
                    if clampedPan <= -0.99 {
                        // Hard left - explicitly silence right
                        lptr[frame] = Float(sample * leftGain)
                        rptr[frame] = 0.0
                    } else if clampedPan >= 0.99 {
                        // Hard right - explicitly silence left
                        lptr[frame] = 0.0
                        rptr[frame] = Float(sample * rightGain)
                    } else {
                        // Anything between, including centre: both channels.
                        lptr[frame] = Float(sample * leftGain)
                        rptr[frame] = Float(sample * rightGain)
                    }

                    // NOTE: per-frame diagnostic `print()` calls used to live
                    // here. String interpolation allocates and takes locks, and
                    // this is an AVAudioSourceNode render callback running on
                    // the real-time audio thread — the one place where that can
                    // cause a buffer underrun, i.e. an audible glitch in the
                    // very tone being measured. `hasLoggedPanInfo` was also
                    // written from here and from `play()` on the main thread
                    // with no synchronisation. Diagnostics belong in
                    // `AudioDiagnosticView`, off this thread.
                }

                localPhase += phaseInc
                if localPhase > twoPi { localPhase -= twoPi }

                localFramesRemaining -= 1
            }

            // Write back updated state
            self.phase = localPhase
            self.framesRemaining = localFramesRemaining
            if self.framesRemaining <= 0 {
                self.playing = false
            }

            return noErr
        }

        // For hearing tests, we need COMPLETE channel isolation
        // Connect source directly to main mixer - the source node callback handles
        // hard panning by writing zeros to one channel, so we don't need an intermediate mixer
        // The mixer node is kept for potential future use but not connected
        mixerNode = AVAudioMixerNode()
        engine.attach(sourceNode)
        engine.attach(mixerNode)
        
        // Connect source DIRECTLY to main mixer for hard panning
        // This ensures no intermediate processing that could mix channels
        engine.connect(sourceNode, to: engine.mainMixerNode, format: stereoFormat)
        
        // Set initial pan on mixer (not used but kept for reference)
        mixerNode.pan = 0.0
        mixerNode.volume = 1.0

        do {
            try engine.start()
        } catch {
            print("AVAudioEngine start error: \(error)")
        }
    }

    /// Play a one-shot tone with the given parameters.
    /// - Parameters:
    ///   - frequency: Hz
    ///   - amplitude: 0.0 - 1.0 (keep conservative; user should keep device volume moderate)
    ///   - pan: -1.0 left, 0 center, +1.0 right
    ///   - duration: seconds
    func play(frequency: Double, amplitude: Double = 0.2, pan: Double = 0.0, duration: TimeInterval = 1.0) {
        self.frequency = max(20, min(20000, frequency))
        self.amplitude = max(0.0, min(1.0, amplitude))
        self.pan = max(-1.0, min(1.0, pan))
        self.hasLoggedPanInfo = false // Reset for new tone
        
        // Note: Mixer node is not in the audio chain for hard panning
        // Channel isolation is handled entirely in the source node render callback
        // which writes zeros to one channel for complete isolation
        print("🎛️ ToneGenerator: Pan set to \(String(format: "%.2f", self.pan)) (hard panning in source callback)")

        let sr = sampleRate
        let frames = Int(duration * sr)
        attackFrames = Int(0.01 * sr) // 10ms
        releaseFrames = Int(0.02 * sr) // 20ms
        totalFramesForThisTone = max(frames, attackFrames + releaseFrames + 1)
        framesRemaining = totalFramesForThisTone
        playing = true

        // Ensure engine is running (it should be)
        if !engine.isRunning {
            do {
                try engine.start()
                print("✅ ToneGenerator: Engine started")
            } catch {
                print("❌ ToneGenerator: Engine restart failed: \(error)")
            }
        } else {
            print("✅ ToneGenerator: Engine already running")
        }
    }
    
    /// Play a calibrated tone at a specific dB HL level
    /// This assumes iOS system volume is at 100% and uses AirPods calibration data
    /// - Parameters:
    ///   - frequency: Frequency in Hz
    ///   - levelDB: Target level in dB HL (Hearing Level)
    ///   - ear: Which ear to present to
    ///   - duration: Duration in seconds (default: 0.5 seconds, clinical standard for pure-tone audiometry)
    ///   - airPodsModel: AirPods model for calibration
    /// Reference: ISO 8253-1 pure-tone audiometry standard
    func playCalibrated(
        frequency: Int,
        levelDB: Double,
        ear: TestEar,
        duration: TimeInterval = 0.5,
        airPodsModel: AirPodsCalibration.ModelType = .airPodsPro
    ) {
        // Calculate amplitude needed to achieve target dB HL
        let amplitude = AirPodsCalibration.amplitudeForTargetHL(
            targetHL: levelDB,
            frequency: frequency,
            model: airPodsModel
        )
        
        // Clamp amplitude to safe range (0.0-1.0)
        let safeAmplitude = max(0.0, min(1.0, amplitude))
        
        // Debug logging to verify amplitude changes
        let splLevel = AirPodsCalibration.convertHLtoSPL(hlDB: levelDB, frequency: frequency)
        print("🎵 Playing tone: \(frequency) Hz, \(levelDB) dB HL (≈\(Int(splLevel)) dB SPL), amplitude: \(String(format: "%.4f", safeAmplitude))")
        
        // Set pan based on ear
        setPanForEar(ear)
        
        // Play the tone
        play(
            frequency: Double(frequency),
            amplitude: safeAmplitude,
            pan: self.pan,
            duration: duration
        )
    }

    func stop() {
        playing = false
        framesRemaining = 0
    }

    func setPanForEar(_ ear: TestEar) {
        switch ear {
        case .left: 
            pan = -1.0
            print("👂 ToneGenerator: Pan set to LEFT ear (-1.0) - ONLY left channel will play")
        case .right: 
            pan = 1.0
            print("👂 ToneGenerator: Pan set to RIGHT ear (+1.0) - ONLY right channel will play")
        case .both: 
            pan = 0.0
            print("👂 ToneGenerator: Pan set to BOTH ears (0.0)")
        }
    }
    
}
