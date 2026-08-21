import Foundation
import AVFoundation
import Combine
import SwiftUI
import CoreBluetooth

/// Central coordinator for hearing test that manages audio session, hardware monitors, and view model
/// Ensures single audio session configuration and reactive state updates via Combine
@MainActor
final class HearingTestCoordinator: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isAudioSessionReady: Bool = false
    @Published var audioSessionError: String?
    
    // MARK: - Owned Components
    
    let routeMonitor: AudioRouteMonitor
    let bluetoothManager: BluetoothAccessManager
    let volumeMonitor: VolumeMonitor
    let noiseMonitor: AmbientNoiseMonitor
    let viewModel: HearingTestViewModel
    
    // MARK: - Audio Session Management
    
    private let audioSession = AVAudioSession.sharedInstance()
    private var cancellables = Set<AnyCancellable>()
    private var wasNoiseMonitoring: Bool = false
    
    // MARK: - Initialization
    
    init() {
        // Initialize hardware monitors first
        self.routeMonitor = AudioRouteMonitor()
        self.bluetoothManager = BluetoothAccessManager()
        self.volumeMonitor = VolumeMonitor()
        self.noiseMonitor = AmbientNoiseMonitor()
        
        // Initialize view model (it will access monitors through coordinator)
        self.viewModel = HearingTestViewModel()
        
        // Inject monitors into view model for backward compatibility
        // Note: ViewModel still has @Published monitors but coordinator owns them
        viewModel.injectMonitors(
            routeMonitor: routeMonitor,
            bluetooth: bluetoothManager,
            volume: volumeMonitor,
            noiseMonitor: noiseMonitor
        )
        
        viewModel.setCoordinator(self)

        // Setup audio session
        setupAudioSession()
        
        // Setup Combine pipelines for reactive state updates
        setupCombinePipelines()
    }
    
    // MARK: - Audio Session Setup
    
    /// Configure audio session once for both playback and recording
    /// Performance: Runs async to avoid blocking UI, but stays on MainActor for audio session
    /// Uses .playAndRecord category to support both tone playback and noise monitoring
    private func setupAudioSession() {
        // Performance: Setup audio session asynchronously to avoid blocking main thread
        Task { @MainActor in
            // Yield to allow UI to render first
            await Task.yield()
            
            do {
                // Single category that satisfies both playback and monitoring needs
                // Note: Removed .defaultToSpeaker to prevent iOS from adjusting volume
                // when switching routes. Headphones are preferred for hearing tests.
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .measurement,
                    options: [.allowBluetooth, .allowBluetoothA2DP]
                )
                
                // Prefer stereo output for proper left/right ear routing
                // This ensures headphones receive stereo signal
                try audioSession.setPreferredOutputNumberOfChannels(2)
                
                try audioSession.setActive(true)
                
                // Log actual output configuration
                let outputChannels = audioSession.outputNumberOfChannels
                print("✅ HearingTestCoordinator: Audio session configured (.playAndRecord)")
                print("🎧 Output channels: \(outputChannels) (preferred: 2)")
                
                // Check for Mono Audio setting (iOS Accessibility) which would mix channels
                if outputChannels < 2 {
                    print("⚠️ WARNING: Output is MONO! Check iPhone Settings → Accessibility → Audio/Visual → Mono Audio (should be OFF)")
                }
                
                isAudioSessionReady = true
                audioSessionError = nil
                
                // Notify components that session is ready
                notifyComponentsOfSessionReady()
                
            } catch {
                isAudioSessionReady = false
                audioSessionError = error.localizedDescription
                print("❌ HearingTestCoordinator: Audio session setup failed: \(error)")
            }
        }
    }
    
    /// Notify ToneGenerator and AmbientNoiseMonitor that shared session is ready
    private func notifyComponentsOfSessionReady() {
        // Components should use the shared session instead of configuring their own
        // This is handled by passing the session reference or using the shared instance
    }
    
    // MARK: - Tone Playback Session Management

    /// Switch to playback-only category to ensure stereo A2DP output (no mic, no HFP mono)
    /// Performance: Runs async to avoid blocking UI, but stays on MainActor for audio session
    func beginTonePlaybackSession() async {
        // Performance: Audio session must be on main thread, but we can yield to avoid blocking
        await Task.yield()
        
        do {
            // Pause noise monitoring to avoid forcing HFP (mono)
            wasNoiseMonitoring = noiseMonitor.isMonitoring
            if wasNoiseMonitoring {
                noiseMonitor.stopMonitoring()
            }

            // Use .playback category with .allowBluetoothA2DP for stereo A2DP output
            // This ensures proper channel isolation on Bluetooth headphones
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            
            // CRITICAL: Force stereo output for proper channel isolation
            try audioSession.setPreferredOutputNumberOfChannels(2)
            
            try audioSession.setActive(true)
            
            // Quick check (minimal logging for performance)
            let outputChannels = audioSession.outputNumberOfChannels
            if outputChannels < 2 {
                print("⚠️ Output is MONO - check Mono Audio setting")
            }
            
        } catch {
            print("❌ Failed to switch to playback category: \(error)")
        }
    }

    /// Restore measurement category for mic/noise monitoring after tone playback
    /// Performance: Runs async to avoid blocking UI, but stays on MainActor for audio session
    func endTonePlaybackSession() async {
        // Performance: Audio session must be on main thread, but we can yield to avoid blocking
        await Task.yield()
        
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setActive(true)

            // Resume noise monitoring if it was running
            if wasNoiseMonitoring {
                noiseMonitor.startMonitoring()
            }
            
        } catch {
            print("❌ Failed to restore playAndRecord category: \(error)")
        }
    }

    // MARK: - Combine Pipelines
    
    /// Replace timer-based polling with reactive Combine pipelines
    private func setupCombinePipelines() {
        // Monitor route changes reactively
        routeMonitor.$currentRoute
            .receive(on: DispatchQueue.main)
            .sink { [weak self] route in
                self?.handleRouteChange(route)
            }
            .store(in: &cancellables)
        
        // Monitor volume changes reactively
        volumeMonitor.$outputVolume
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] volume in
                self?.handleVolumeChange(volume)
            }
            .store(in: &cancellables)
        
        // Monitor noise level changes reactively
        noiseMonitor.$currentNoiseLevel
            .receive(on: DispatchQueue.main)
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] noiseLevel in
                self?.handleNoiseLevelChange(noiseLevel)
            }
            .store(in: &cancellables)
        
        // Monitor Bluetooth readiness reactively
        // Combine authorization and power state to compute readiness
        Publishers.CombineLatest(
            bluetoothManager.$authorization,
            bluetoothManager.$isPoweredOn
        )
        .receive(on: DispatchQueue.main)
        .map { authorization, isPoweredOn -> Bool in
            // Compute isReady from published properties (matches BluetoothAccessManager.isReady logic)
            let isAuthorized: Bool
            if #available(iOS 13.0, *) {
                isAuthorized = authorization == .allowedAlways
            } else {
                isAuthorized = true
            }
            return isAuthorized && isPoweredOn
        }
        .sink { [weak self] isReady in
            self?.handleBluetoothReadyChange(isReady)
        }
        .store(in: &cancellables)
    }
    
    // MARK: - Reactive Handlers
    
    private func handleRouteChange(_ route: AudioRouteMonitor.RouteKind) {
        // Update view model state based on route
        // Route changes trigger UI updates automatically via Combine
        print("🔄 Route changed: \(route)")
    }
    
    private func handleVolumeChange(_ volume: Float) {
        // Volume changes trigger UI updates automatically
        // No need for polling - Combine handles it
        print("🔊 Volume changed: \(volume)")
    }
    
    private func handleNoiseLevelChange(_ noiseLevel: Float) {
        // Noise level changes trigger UI updates automatically
        print("🌊 Noise level changed: \(noiseLevel) dB")
    }
    
    private func handleBluetoothReadyChange(_ isReady: Bool) {
        // Bluetooth readiness changes trigger UI updates automatically
        print("📶 Bluetooth ready: \(isReady)")
    }
    
    // MARK: - Public Interface
    
    /// Request microphone permission for noise monitoring
    func requestMicrophonePermission() {
        noiseMonitor.requestMicrophonePermission()
    }
    
    /// Start noise monitoring
    func startNoiseMonitoring() {
        guard isAudioSessionReady else {
            print("⚠️ Cannot start noise monitoring - audio session not ready")
            return
        }
        noiseMonitor.startMonitoring()
    }
    
    /// Stop noise monitoring
    func stopNoiseMonitoring() {
        noiseMonitor.stopMonitoring()
    }
    
    /// Get shared audio session (for components that need direct access)
    var sharedAudioSession: AVAudioSession {
        return audioSession
    }
}
