import Foundation
import AVFoundation
import Combine

/// Monitors the current audio output route and provides simple status about headphone/earbud connectivity.
final class AudioRouteMonitor: ObservableObject {
    enum RouteKind: Equatable {
        case wiredHeadphones
        case bluetooth(name: String?)
        case airPods(name: String?)
        case builtInSpeaker
        case other(String)
    }

    @Published var currentRoute: RouteKind = .other("Unknown")
    @Published var isHeadphoneLikeConnected: Bool = false

    /// True when the active output is applying spatial audio processing.
    ///
    /// **This invalidates the entire test when it is on.** Spatial audio mixes
    /// and re-renders both channels, which defeats the one-silent-channel
    /// stereo trick the per-ear measurement depends on: the tone intended for
    /// the left ear is audible in both, so every per-ear result is meaningless.
    ///
    /// `CRITICAL_FIX_README.md` documented this as something the user must go
    /// and switch off in Settings, and nothing in the app ever checked. It is
    /// directly observable: `isSpatialAudioEnabled` has been on
    /// `AVAudioSessionPortDescription` since iOS 15, and
    /// `spatialPlaybackCapabilitiesChanged` fires when the user changes it
    /// mid-session. A hearing test should refuse to run rather than hand back
    /// a number it knows is wrong.
    @Published var isSpatialAudioActive: Bool = false

    private let session = AVAudioSession.sharedInstance()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        refresh()
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        // Spatial audio can be toggled without a route change, so the route
        // notification alone is not enough to keep `isSpatialAudioActive` true
        // to reality mid-test.
        NotificationCenter.default
            .publisher(for: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        let route = session.currentRoute
        guard let output = route.outputs.first else {
            currentRoute = .other("No Output")
            isHeadphoneLikeConnected = false
            isSpatialAudioActive = false
            return
        }

        isSpatialAudioActive = route.outputs.contains { $0.isSpatialAudioEnabled }

        let name = output.portName
        switch output.portType {
        case .headphones, .headsetMic:
            currentRoute = .wiredHeadphones
            isHeadphoneLikeConnected = true
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            // Heuristic: consider AirPods if name contains "AirPods"
            if name.localizedCaseInsensitiveContains("airpods") {
                currentRoute = .airPods(name: name)
            } else {
                currentRoute = .bluetooth(name: name)
            }
            isHeadphoneLikeConnected = true
        case .builtInSpeaker:
            currentRoute = .builtInSpeaker
            isHeadphoneLikeConnected = false
        default:
            currentRoute = .other(output.portType.rawValue)
            // Consider other outputs as not ideal for hearing test
            isHeadphoneLikeConnected = false
        }
    }

    var routeDescription: String {
        switch currentRoute {
        case .wiredHeadphones:
            return "Wired headphones connected"
        case .bluetooth(let name):
            return "Bluetooth headphones connected\(name.map { " (\($0))" } ?? "")"
        case .airPods(let name):
            return "AirPods connected\(name.map { " (\($0))" } ?? "")"
        case .builtInSpeaker:
            return "Built-in speaker"
        case .other(let s):
            return s
        }
    }
}
