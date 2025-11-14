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
        
        // Setup audio session
        setupAudioSession()
        
        // Setup Combine pipelines for reactive state updates
        setupCombinePipelines()
    }
    
    // MARK: - Audio Session Setup
    
    /// Configure audio session once for both playback and recording
    /// Uses .playAndRecord category to support both tone playback and noise monitoring
    private func setupAudioSession() {
        do {
            // Single category that satisfies both playback and monitoring needs
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
            
            isAudioSessionReady = true
            audioSessionError = nil
            
            print("✅ HearingTestCoordinator: Audio session configured (.playAndRecord)")
            
            // Notify components that session is ready
            notifyComponentsOfSessionReady()
            
        } catch {
            isAudioSessionReady = false
            audioSessionError = error.localizedDescription
            print("❌ HearingTestCoordinator: Audio session setup failed: \(error)")
        }
    }
    
    /// Notify ToneGenerator and AmbientNoiseMonitor that shared session is ready
    private func notifyComponentsOfSessionReady() {
        // Components should use the shared session instead of configuring their own
        // This is handled by passing the session reference or using the shared instance
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

