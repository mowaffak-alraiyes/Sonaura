import Foundation
import AVFoundation
import Combine

/// Monitors ambient noise level using the device microphone
/// to ensure test environment is quiet enough for accurate hearing threshold detection
@MainActor
final class AmbientNoiseMonitor: ObservableObject {
    
    @Published var currentNoiseLevel: Float = 0.0 // dB SPL estimate
    @Published var isQuietEnough: Bool = true
    @Published var isMonitoring: Bool = false
    @Published var microphonePermissionGranted: Bool = false
    
    private let engine = AVAudioEngine()
    // Use shared audio session instead of creating our own
    // The coordinator manages the session configuration
    private let session = AVAudioSession.sharedInstance()
    private var cancellables = Set<AnyCancellable>()
    
    // Threshold for acceptable background noise (dB SPL)
    // Clinical audiometry requires < 30 dB ambient noise
    // We'll use 40 dB as a more practical threshold for home testing
    private let maxAcceptableNoiseDB: Float = 40.0
    
    // Sample rate for analysis
    private let sampleRate: Double = 44100.0
    private var analysisBuffer: [Float] = []
    private let analysisWindowSize = 2048
    
    init() {
        checkMicrophonePermission()
    }
    
    /// Request microphone permission if not already granted
    func requestMicrophonePermission() {
        // Use legacy API to avoid iOS 17 compatibility issues
        session.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                self?.microphonePermissionGranted = granted
                if granted {
                    self?.setupAudioSession()
                }
            }
        }
    }
    
    /// Check current microphone permission status
    private func checkMicrophonePermission() {
        // For now, use the legacy API to avoid iOS 17 compatibility issues
        let permission = session.recordPermission
        switch permission {
        case .granted:
            microphonePermissionGranted = true
            setupAudioSession()
        case .denied:
            microphonePermissionGranted = false
        case .undetermined:
            microphonePermissionGranted = false
        @unknown default:
            microphonePermissionGranted = false
        }
    }
    
    /// Audio session is configured by HearingTestCoordinator
    /// This method is kept for backward compatibility but does not reconfigure the session
    private func setupAudioSession() {
        // Session is managed by HearingTestCoordinator
        // Just check if it's ready and proceed with engine setup
        guard session.category == .playAndRecord else {
            print("⚠️ AmbientNoiseMonitor: Audio session not configured by coordinator yet")
            return
        }
        
        // Give the session a moment to stabilize
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.setupEngineIfReady()
        }
    }
    
    /// Setup engine only when audio session is ready
    private func setupEngineIfReady() {
        guard session.isOtherAudioPlaying == false else {
            print("AmbientNoiseMonitor: Other audio is playing, waiting...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.setupEngineIfReady()
            }
            return
        }
        
        // Engine setup will happen when startMonitoring is called
        print("AmbientNoiseMonitor: Audio session ready")
    }
    
    /// Start monitoring ambient noise
    func startMonitoring() {
        guard microphonePermissionGranted else {
            requestMicrophonePermission()
            return
        }
        
        guard !isMonitoring else { return }
        
        // Ensure audio session is active
        guard session.category == .playAndRecord else {
            setupAudioSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.startMonitoring()
            }
            return
        }
        
        setupEngine()
        
        do {
            try engine.start()
            isMonitoring = true
            print("AmbientNoiseMonitor: Started monitoring")
        } catch {
            print("AmbientNoiseMonitor: Failed to start engine: \(error)")
            // Reset monitoring state on failure
            isMonitoring = false
        }
    }
    
    /// Stop monitoring ambient noise
    func stopMonitoring() {
        guard isMonitoring else { return }
        
        engine.stop()
        isMonitoring = false
    }
    
    /// Setup audio engine to capture and analyze microphone input
    private func setupEngine() {
        let inputNode = engine.inputNode
        
        // Use the input node's actual format to avoid format mismatches
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Validate the input format
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            print("AmbientNoiseMonitor: Invalid input format - sampleRate: \(inputFormat.sampleRate), channelCount: \(inputFormat.channelCount)")
            return
        }
        
        print("AmbientNoiseMonitor: Using input format - \(inputFormat.sampleRate) Hz, \(inputFormat.channelCount) channels, \(inputFormat.commonFormat.rawValue)")
        
        // Install tap using the input node's actual format
        inputNode.installTap(onBus: 0, bufferSize: AVAudioFrameCount(analysisWindowSize), format: inputFormat) { [weak self] buffer, _ in
            self?.analyzeBuffer(buffer)
        }
        
        engine.prepare()
    }
    
    /// Analyze audio buffer to estimate noise level
    private func analyzeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // Calculate RMS (root mean square) of the audio signal
        let rms = calculateRMS(samples: samples)
        
        // Convert RMS amplitude to dB
        // Reference: 0 dBFS (full scale) = 1.0 amplitude
        // Typical microphone noise floor is around -60 to -40 dBFS
        let dbFS = amplitudeToDB(rms)
        
        // Estimate dB SPL from dBFS
        // This is approximate - actual calibration would require a reference sound source
        // We assume smartphone mic at normal gain has roughly:
        // -40 dBFS ≈ 30 dB SPL (quiet room)
        // -20 dBFS ≈ 50 dB SPL (normal conversation distance)
        //   0 dBFS ≈ 90 dB SPL (very loud)
        let estimatedSPL = estimateSPLFromDBFS(dbFS)
        
        Task { @MainActor in
            self.currentNoiseLevel = estimatedSPL
            self.isQuietEnough = estimatedSPL < self.maxAcceptableNoiseDB
        }
    }
    
    /// Calculate RMS (root mean square) amplitude
    private func calculateRMS(samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0.0 }
        
        let sumOfSquares = samples.reduce(0.0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }
    
    /// Convert linear amplitude to decibels
    private func amplitudeToDB(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return -160.0 } // Floor at -160 dB
        return 20.0 * log10(amplitude)
    }
    
    /// Estimate SPL from dBFS using empirical calibration curve
    /// This is an approximation - actual values vary by device and environment
    private func estimateSPLFromDBFS(_ dbFS: Float) -> Float {
        // Empirical mapping for typical smartphone microphones
        // This is a rough approximation and ideally would be calibrated per device
        
        // Linear mapping: -60 dBFS → 20 dB SPL, 0 dBFS → 90 dB SPL
        let slope: Float = 70.0 / 60.0 // (90-20) / (0-(-60))
        let intercept: Float = 90.0
        
        let estimatedSPL = slope * dbFS + intercept
        
        // Clamp to reasonable range
        return max(0.0, min(120.0, estimatedSPL))
    }
    
    /// Get noise level status message
    var noiseStatusMessage: String {
        if !microphonePermissionGranted {
            return "Microphone access needed to check ambient noise"
        }
        
        if !isMonitoring {
            return "Tap to check ambient noise level"
        }
        
        if isQuietEnough {
            return "✓ Environment is quiet enough (~\(Int(currentNoiseLevel)) dB)"
        } else {
            return "⚠️ Too noisy for accurate testing (~\(Int(currentNoiseLevel)) dB)"
        }
    }
    
    var noiseRecommendation: String? {
        guard isMonitoring && !isQuietEnough else { return nil }
        
        let excessNoise = Int(currentNoiseLevel - maxAcceptableNoiseDB)
        return "Find a quieter location. Current noise is ~\(excessNoise) dB above recommended maximum. Try a quiet room away from HVAC, traffic, and conversations."
    }
    
    deinit {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }
}

