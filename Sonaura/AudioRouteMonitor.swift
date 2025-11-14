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

    private let session = AVAudioSession.sharedInstance()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        refresh()
        NotificationCenter.default
            .publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        let route = session.currentRoute
        guard let output = route.outputs.first else {
            currentRoute = .other("No Output")
            isHeadphoneLikeConnected = false
            return
        }

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
