//
//  TonePlayer.swift
//  Sonaura
//
//  Tone player using STEREO audio with one silent channel
//  This bypasses all pan/mixing - audio goes directly to the correct channel
//

import Foundation
import AVFoundation

enum EarChannel {
    case left
    case right
    case both
}

/// Tone player that generates stereo WAV with audio in only one channel
/// This is the most direct approach - no pan, no mixing, just raw channel data
final class TonePlayer {
    private var audioPlayer: AVAudioPlayer?
    private let audioSession = AVAudioSession.sharedInstance()
    
    // Route change observer
    private var routeChangeObserver: NSObjectProtocol?
    
    init() {
        setupAudioSession()
        setupRouteChangeMonitoring()
        printFullDiagnostics()
    }
    
    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Diagnostics
    
    private func printFullDiagnostics() {
        print("═══════════════════════════════════════════")
        print("🔍 AUDIO DIAGNOSTICS")
        print("═══════════════════════════════════════════")
        
        // Audio session info
        print("📱 Audio Session:")
        print("   Category: \(audioSession.category.rawValue)")
        print("   Mode: \(audioSession.mode.rawValue)")
        print("   Output Channels: \(audioSession.outputNumberOfChannels)")
        print("   Input Channels: \(audioSession.inputNumberOfChannels)")
        print("   Sample Rate: \(audioSession.sampleRate)")
        
        // Output route
        print("🔊 Output Route:")
        for output in audioSession.currentRoute.outputs {
            print("   Port: \(output.portName)")
            print("   Type: \(output.portType.rawValue)")
            print("   UID: \(output.uid)")
            print("   Channels: \(output.channels?.count ?? 0)")
            if let channels = output.channels {
                for (i, ch) in channels.enumerated() {
                    print("      Channel \(i): \(ch.channelName) (label: \(ch.channelLabel))")
                }
            }
        }
        
        // Check for problematic settings
        print("⚠️ Potential Issues:")
        if audioSession.outputNumberOfChannels < 2 {
            print("   ❌ OUTPUT IS MONO - This will cause both-ear playback!")
        }
        
        for output in audioSession.currentRoute.outputs {
            if output.portType == .bluetoothHFP {
                print("   ❌ Using Bluetooth HFP (phone call mode) - MONO only!")
                print("      Try disconnecting and reconnecting AirPods")
            }
            if output.portType == .bluetoothA2DP {
                print("   ✅ Using Bluetooth A2DP (stereo mode)")
            }
        }
        
        print("═══════════════════════════════════════════")
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        do {
            // Use playback category - this should give us A2DP stereo
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setActive(true)
            
            print("✅ TonePlayer: Audio session configured")
        } catch {
            print("❌ TonePlayer: Audio session setup failed: \(error)")
        }
    }
    
    // MARK: - STEREO Tone Generation (one channel silent)
    
    /// Generate a STEREO WAV file with audio in only one channel
    /// This bypasses pan entirely - the silent channel has actual zeros
    private func generateStereoToneData(frequency: Double, duration: Double, amplitude: Float, ear: EarChannel) -> Data {
        let sampleRate: Double = 44100
        let numSamples = Int(sampleRate * duration)
        let numChannels: UInt16 = 2  // STEREO
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = numChannels * bytesPerSample
        let byteRate = UInt32(sampleRate) * UInt32(blockAlign)
        let dataSize = UInt32(numSamples * Int(blockAlign))
        
        var data = Data()
        
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
        
        // Generate stereo samples
        let twoPi = 2.0 * Double.pi
        let attackSamples = Int(0.01 * sampleRate)
        let releaseSamples = Int(0.02 * sampleRate)
        
        for i in 0..<numSamples {
            // Envelope
            let envelope: Double
            if i < attackSamples {
                envelope = Double(i) / Double(attackSamples)
            } else if i >= numSamples - releaseSamples {
                let releasePos = i - (numSamples - releaseSamples)
                envelope = 1.0 - Double(releasePos) / Double(releaseSamples)
            } else {
                envelope = 1.0
            }
            
            // Generate sample
            let sample = sin(twoPi * frequency * Double(i) / sampleRate) * Double(amplitude) * envelope
            let intSample = Int16(max(-32768, min(32767, sample * 32767)))
            let silence = Int16(0)
            
            // Write LEFT then RIGHT sample (interleaved stereo)
            let leftSample: Int16
            let rightSample: Int16
            
            switch ear {
            case .left:
                leftSample = intSample   // Audio in LEFT
                rightSample = silence    // Silence in RIGHT
            case .right:
                leftSample = silence     // Silence in LEFT
                rightSample = intSample  // Audio in RIGHT
            case .both:
                leftSample = intSample   // Audio in both
                rightSample = intSample
            }
            
            data.append(contentsOf: withUnsafeBytes(of: leftSample.littleEndian) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: rightSample.littleEndian) { Array($0) })
        }
        
        return data
    }
    
    // MARK: - Public Interface
    
    /// Play a tone to a specific ear using STEREO audio with one silent channel
    func playTone(frequency: Double, duration: Double, ear: EarChannel, level: Float) {
        // Refresh audio session
        do {
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP]
            )
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setActive(true)
        } catch {
            print("⚠️ TonePlayer: Audio session error: \(error)")
        }
        
        // Print diagnostics
        printFullDiagnostics()
        
        // Generate STEREO tone with audio in only one channel
        let toneData = generateStereoToneData(
            frequency: frequency,
            duration: duration,
            amplitude: level,
            ear: ear
        )
        
        do {
            audioPlayer = try AVAudioPlayer(data: toneData)
            
            guard let player = audioPlayer else {
                print("❌ TonePlayer: Failed to create player")
                return
            }
            
            // Don't use pan - the stereo file already has the correct channel layout
            player.pan = 0.0  // Center - let the stereo file do the work
            
            player.prepareToPlay()
            player.play()
            
            let earName: String
            switch ear {
            case .left: earName = "LEFT (L=audio, R=silence)"
            case .right: earName = "RIGHT (L=silence, R=audio)"
            case .both: earName = "BOTH (L=audio, R=audio)"
            }
            
            print("═══════════════════════════════════════════")
            print("🔊 PLAYING TONE")
            print("═══════════════════════════════════════════")
            print("   Frequency: \(Int(frequency)) Hz")
            print("   Duration: \(duration)s")
            print("   Level: \(level)")
            print("   Target: \(earName)")
            print("   Method: STEREO WAV with silent channel")
            print("   Player channels: \(player.numberOfChannels)")
            print("═══════════════════════════════════════════")
            
            if player.numberOfChannels != 2 {
                print("⚠️ WARNING: Player has \(player.numberOfChannels) channels, expected 2!")
            }
            
        } catch {
            print("❌ TonePlayer: Failed to play: \(error)")
        }
    }
    
    /// Stop playing
    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        print("🛑 TonePlayer: Stopped")
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
            print("🔄 Route changed!")
            self.printFullDiagnostics()
        }
    }
}
