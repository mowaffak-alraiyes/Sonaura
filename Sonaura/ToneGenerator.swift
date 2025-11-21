import Foundation
import AVFoundation

/// Simple sine-wave tone generator using AVAudioEngine + AVAudioSourceNode.
/// Supports equal-power panning for left/right ear presentation and a short attack/release envelope to avoid clicks.
final class ToneGenerator {
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode!
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

    // Gating/envelope for one-shot playback
    private var playing: Bool = false
    private var framesRemaining: Int = 0
    private var attackFrames: Int = 0
    private var releaseFrames: Int = 0
    private var totalFramesForThisTone: Int = 0

    init() {
        // Don't configure session here - coordinator handles it
        // Just setup the engine
        setupEngine()
    }

    private func setupEngine() {
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = outFormat.sampleRate

        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let channels = Int(abl.count)
            let frames = Int(frameCount)

            if channels == 0 { return noErr }

            // Precompute equal-power pan gains
            let clampedPan = max(-1.0, min(1.0, self.pan))
            // Map [-1,1] -> [0,1] then to angle [0, pi/2]
            let angle = (clampedPan + 1.0) * .pi / 4.0
            let leftGain = cos(angle)
            let rightGain = sin(angle)

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
                    let ptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = Float(sample)
                } else {
                    let lptr = abl[0].mData!.assumingMemoryBound(to: Float.self)
                    let rptr = abl[1].mData!.assumingMemoryBound(to: Float.self)
                    lptr[frame] = Float(sample * leftGain)
                    rptr[frame] = Float(sample * rightGain)
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

        // Match the output format for best compatibility (e.g., stereo to headphones)
        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: engine.outputNode.outputFormat(forBus: 0))

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
        case .left: pan = -1.0
        case .right: pan = 1.0
        case .both: pan = 0.0
        }
    }
}
