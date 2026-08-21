//
//  TonePlayer.swift
//  Sonaura
//
//  Optimized tone player with preloaded buffers and background processing
//  Performance: Preloads common tones, offloads generation to background thread
//

import Foundation
import AVFoundation

enum EarChannel {
    case left
    case right
    case both
}

/// Optimized tone player with preloaded buffers for instant playback
/// Performance optimizations:
/// - Preloads common tone frequencies
/// - Generates audio on background thread
/// - Caches generated WAV data
/// - Reuses AVAudioPlayer instances
final class TonePlayer {
    private var audioPlayer: AVAudioPlayer?
    private let audioSession = AVAudioSession.sharedInstance()
    
    // Performance: Cache for preloaded tone data
    private var toneCache: [String: Data] = [:]
    private let cacheQueue = DispatchQueue(label: "com.sonaura.tonecache", attributes: .concurrent)
    
    // Performance: Preload common frequencies in background
    private var isPreloading = false
    
    // Route change observer
    private var routeChangeObserver: NSObjectProtocol?
    
    init() {
        // Performance: Setup audio session on background thread
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.setupAudioSession()
        }
        
        setupRouteChangeMonitoring()
        
        // Performance: Preload common tones in background (non-blocking)
        Task.detached(priority: .utility) { [weak self] in
            await self?.preloadCommonTones()
        }
    }
    
    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Audio Session Setup (Background)
    
    /// Setup audio session on background thread to avoid blocking UI
    private func setupAudioSession() async {
        do {
            // Use playback category - this should give us A2DP stereo
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setActive(true)
            
            print("✅ TonePlayer: Audio session configured (background)")
        } catch {
            print("❌ TonePlayer: Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - Tone Preloading (Performance)
    
    /// Preloading is deliberately disabled. See the reasoning below before
    /// re-enabling it.
    ///
    /// The old implementation preloaded twelve tones at a hardcoded
    /// `amplitude: Float = 0.2` described as "typical". No presentation ever
    /// uses that amplitude: the real value comes out of `AirPodsCalibration`
    /// and depends on the headphone model, the frequency and the target dB HL,
    /// and lands around 1e-5 to 1e-4. So every preloaded entry was a guaranteed
    /// cache miss — roughly a megabyte of WAV data generated at launch that
    /// nothing could ever read. (It only *looked* like it worked because the
    /// old truncating cache key collapsed unrelated amplitudes together.)
    ///
    /// Preloading correctly would mean knowing the connected model and the
    /// full level ladder at init, which is not available here. Generating on
    /// demand on a background thread is already fast enough for a test that
    /// waits for a user tap between presentations.
    ///
    /// The old version also raced: each child task read `toneCache` directly
    /// while its siblings wrote through `cacheQueue.async(flags: .barrier)`.
    /// Unsynchronised concurrent read/write on a Swift `Dictionary` is
    /// undefined behaviour, and this ran from `init`, so the exposure was at
    /// every launch. Any future reinstatement must read through
    /// `cacheQueue.sync` the way `playTone` does.
    private func preloadCommonTones() async {
        // Intentionally empty.
    }
    
    /// Generate cache key for tone
    /// Cache key. Amplitude is encoded as its exact bit pattern.
    ///
    /// This was `Int(amplitude * 1000)`, and that single expression disabled
    /// the entire hearing test. Screening amplitudes run about 1e-5 to 1e-4,
    /// so `amplitude * 1000` is well under 1 and `Int(...)` truncates every one
    /// of them to `0`. All four rungs of the ladder at a given frequency and
    /// ear therefore produced the *same* key: the 15 dB HL tone was generated
    /// and cached, and the 25, 40 and 55 dB HL presentations each scored a
    /// cache hit and replayed that same quiet WAV at the same loudness.
    ///
    /// The app was not measuring a threshold. It played one fixed tone up to
    /// four times and recorded whether the user heard it.
    ///
    /// `bitPattern` cannot collide for distinct amplitudes and cannot lose
    /// precision, which is the property this key actually needs.
    private func cacheKey(frequency: Double, duration: Double, amplitude: Float, ear: EarChannel) -> String {
        let earStr: String
        switch ear {
        case .left: earStr = "L"
        case .right: earStr = "R"
        case .both: earStr = "B"
        }
        return "\(Int(frequency))Hz_\(Int(duration * 1000))ms_amp\(amplitude.bitPattern)_\(earStr)"
    }

    #if DEBUG
    /// Test seam for `cacheKey`. A key collision fails silently at runtime —
    /// it replays the wrong audio rather than erroring — so it has to be
    /// asserted on directly. See `ToneCacheTests`.
    func debugCacheKey(frequency: Double, duration: Double, amplitude: Float, ear: EarChannel) -> String {
        cacheKey(frequency: frequency, duration: duration, amplitude: amplitude, ear: ear)
    }
    #endif
    
    // MARK: - STEREO Tone Generation (Background)
    
    /// Generate a STEREO WAV file with audio in only one channel (background thread)
    /// Performance: Runs on background thread to avoid blocking UI
    private func generateStereoToneData(frequency: Double, duration: Double, amplitude: Float, ear: EarChannel) async -> Data {
        return await Task.detached(priority: .userInitiated) {
            let sampleRate: Double = 44100
            let numSamples = Int(sampleRate * duration)
            let numChannels: UInt16 = 2  // STEREO
            let bitsPerSample: UInt16 = 16
            let bytesPerSample = bitsPerSample / 8
            let blockAlign = numChannels * bytesPerSample
            let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
            let dataSize = UInt32(numSamples * Int(blockAlign))
            
            var data = Data()
            data.reserveCapacity(Int(36 + dataSize)) // Pre-allocate capacity for performance
            
            // RIFF header
            data.append(contentsOf: "RIFF".utf8)
            let fileSize = 36 + dataSize
            data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
            data.append(contentsOf: "WAVE".utf8)
            
            // fmt chunk
            data.append(contentsOf: "fmt ".utf8)
            data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM
            data.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) }) // STEREO
            data.append(contentsOf: withUnsafeBytes(of: UInt32(44100).littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })
            
            // data chunk
            data.append(contentsOf: "data".utf8)
            data.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })
            
            // Generate stereo samples (optimized loop)
            let twoPi = 2.0 * Double.pi
            let attackSamples = Int(0.01 * sampleRate)
            let releaseSamples = Int(0.02 * sampleRate)
            let phaseIncrement = twoPi * frequency / sampleRate
            
            // Pre-calculate envelope values for performance
            var envelopeValues = [Double](repeating: 1.0, count: numSamples)
            for i in 0..<attackSamples {
                envelopeValues[i] = Double(i) / Double(attackSamples)
            }
            for i in (numSamples - releaseSamples)..<numSamples {
                let releasePos = i - (numSamples - releaseSamples)
                envelopeValues[i] = 1.0 - Double(releasePos) / Double(releaseSamples)
            }
            
            // Generate samples (optimized)
            let silence = Int16(0)
            let amplitudeDouble = Double(amplitude)
            
            // Verify amplitude produces audible samples
            let expectedMaxSample = Int(amplitudeDouble * 32767)
            if expectedMaxSample < 3 {
                print("⚠️ WARNING: Amplitude \(String(format: "%.8f", amplitudeDouble)) may produce inaudible samples")
                print("   Expected max sample value: \(expectedMaxSample) (minimum for audibility: 3)")
                print("   Frequency: \(Int(frequency)) Hz, Duration: \(duration)s, Ear: \(ear)")
            }
            
            for i in 0..<numSamples {
                let sample = sin(phaseIncrement * Double(i)) * amplitudeDouble * envelopeValues[i]
                let intSample = Int16(max(-32768, min(32767, sample * 32767)))
                
                // Write LEFT then RIGHT sample (interleaved stereo)
                let leftSample: Int16
                let rightSample: Int16
                
                switch ear {
                case .left:
                    leftSample = intSample
                    rightSample = silence
                case .right:
                    leftSample = silence
                    rightSample = intSample
                case .both:
                    leftSample = intSample
                    rightSample = intSample
                }
                
                data.append(contentsOf: withUnsafeBytes(of: leftSample.littleEndian) { Array($0) })
                data.append(contentsOf: withUnsafeBytes(of: rightSample.littleEndian) { Array($0) })
            }
            
            return data
        }.value
    }
    
    // MARK: - Public Interface (Optimized)
    
    /// Amplitude the WAV samples are actually written at.
    ///
    /// Half of full scale: high enough that 16-bit quantisation is irrelevant
    /// (samples around ±16383), low enough to leave headroom. The real, much
    /// smaller test level is applied afterwards by `AVAudioPlayer.volume`.
    static let carrierAmplitude: Float = 0.5

    /// Play a tone to a specific ear using STEREO audio with one silent channel.
    ///
    /// `level` is the true calibrated amplitude from `AirPodsCalibration`, and
    /// it is **not** baked into the samples. Samples are generated once per
    /// frequency/ear at `carrierAmplitude`, and the attenuation from there down
    /// to `level` is applied by `AVAudioPlayer.volume`.
    ///
    /// This is what makes low levels honest. Writing a 2.5e-5 amplitude into
    /// 16-bit PCM gives a sample value of 0 — the tone is silent — which is
    /// what drove the old minimum-amplitude clamp in `AirPodsCalibration` and
    /// with it the +6 to +10 dB error across the screening boundary. Player
    /// volume is applied in the float domain and has no such floor.
    ///
    /// It also makes the cache work for the first time: one WAV per
    /// frequency/duration/ear now serves every level in the ladder.
    ///
    /// - Returns: `false` if the requested level cannot be produced (it would
    ///   need a player volume above 1.0). Refusing is deliberate — presenting
    ///   an unreachable level at the wrong loudness is what produced false
    ///   "normal hearing" results.
    @discardableResult
    func playTone(frequency: Double, duration: Double, ear: EarChannel, level: Float) -> Bool {
        let playbackVolume = level / Self.carrierAmplitude
        guard playbackVolume <= 1.0 else {
            print("❌ TonePlayer: level \(level) exceeds carrier \(Self.carrierAmplitude) — refusing to present \(frequency) Hz. Raise carrierAmplitude or treat this level as unreachable.")
            return false
        }
        guard playbackVolume > 0 else {
            print("❌ TonePlayer: non-positive level \(level) for \(frequency) Hz — refusing.")
            return false
        }

        // Cache on the carrier amplitude, not the level: the samples are
        // identical across levels now.
        let cacheKey = self.cacheKey(frequency: frequency, duration: duration, amplitude: Self.carrierAmplitude, ear: ear)

        // Try to get from cache (thread-safe read)
        let cachedData = cacheQueue.sync {
            return toneCache[cacheKey]
        }

        if let cachedData = cachedData {
            // Performance: Use cached data (instant playback)
            playCachedTone(data: cachedData, volume: playbackVolume)
        } else {
            // Performance: Generate on background thread, then play
            Task { @MainActor in
                let toneData = await generateStereoToneData(
                    frequency: frequency,
                    duration: duration,
                    amplitude: Self.carrierAmplitude,
                    ear: ear
                )

                // Cache for future use
                cacheQueue.async(flags: .barrier) { [weak self] in
                    self?.toneCache[cacheKey] = toneData
                }

                // Play immediately
                await MainActor.run {
                    self.playToneData(toneData, volume: playbackVolume)
                }
            }
        }
        return true
    }
    
    /// Play cached tone data (main thread, instant)
    private func playCachedTone(data: Data, volume: Float) {
        // Ensure audio session is active (quick check)
        Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.audioSession.setActive(true)
            } catch {
                // Ignore - might already be active
            }
        }

        // Play immediately on main thread
        playToneData(data, volume: volume)
    }

    /// Internal method to play tone data (main thread)
    private func playToneData(_ toneData: Data, volume: Float) {
        do {
            // Performance: Reuse player if possible
            if audioPlayer == nil {
                audioPlayer = try AVAudioPlayer(data: toneData)
            } else {
                // Try to reuse existing player
                audioPlayer = try AVAudioPlayer(data: toneData)
            }
            
            guard let player = audioPlayer else {
                print("❌ TonePlayer: Failed to create player")
                return
            }
            
            // CRITICAL: Verify player configuration
            print("🎵 TonePlayer: Playing tone")
            print("   Player channels: \(player.numberOfChannels)")
            print("   Audio session channels: \(audioSession.outputNumberOfChannels)")
            print("   System volume: \(audioSession.outputVolume)")
            print("   Route: \(audioSession.currentRoute.outputs.first?.portName ?? "Unknown")")
            
            if player.numberOfChannels != 2 {
                print("⚠️ WARNING: Player reports \(player.numberOfChannels) channels (expected 2)")
            }
            
            if audioSession.outputNumberOfChannels < 2 {
                print("⚠️ WARNING: Audio session is MONO - channel isolation will fail!")
            }
            
            if audioSession.outputVolume < 0.95 {
                print("⚠️ WARNING: System volume is \(Int(audioSession.outputVolume * 100))% - should be 100%")
            }
            
            player.pan = 0.0  // Center - let the stereo file do the work
            // The calibrated attenuation lives here, not in the samples. This
            // was pinned to 1.0, which is precisely why the level had to be
            // baked into 16-bit samples and then clamped to stay audible.
            player.volume = volume
            player.prepareToPlay()
            
            let didPlay = player.play()
            if !didPlay {
                print("❌ TonePlayer: play() returned false - tone may not play")
            } else {
                print("✅ TonePlayer: play() returned true - tone should be playing")
            }
            
        } catch {
            print("❌ TonePlayer: Failed to play: \(error)")
        }
    }
    
    /// Stop playing
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    /// Check if headphones are connected
    func areHeadphonesConnected() -> Bool {
        let route = audioSession.currentRoute
        guard let output = route.outputs.first else { return false }
        
        switch output.portType {
        case .headphones, .headsetMic, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return true
        default:
            return false
        }
    }
    
    /// Get current audio route
    func getCurrentRoute() -> String {
        audioSession.currentRoute.outputs.first?.portName ?? "No Output"
    }
    
    // MARK: - Route Change Monitoring
    
    private func setupRouteChangeMonitoring() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Performance: Don't print diagnostics on every route change (only log)
            print("🔄 TonePlayer: Route changed")
        }
    }
}
