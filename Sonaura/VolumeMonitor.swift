import Foundation
import AVFoundation
import Combine

/// Observes system output volume (read-only) so we can tell whether the device is at/near max.
/// Note: iOS does not allow apps to set the system volume programmatically.
final class VolumeMonitor: NSObject, ObservableObject {
    @Published var outputVolume: Float = AVAudioSession.sharedInstance().outputVolume

    private var observation: NSKeyValueObservation?

    override init() {
        super.init()
        start()
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Activate ensures we can read volume; uses current category.
            try session.setActive(true, options: [])
        } catch {
            // Non-fatal; we'll still try to observe.
            print("VolumeMonitor: setActive error: \(error)")
        }

        // Observe using KVO to get live updates when the user changes volume.
        observation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let self else { return }
            if let v = change.newValue {
                DispatchQueue.main.async {
                    self.outputVolume = v
                }
            }
        }

        // Seed initial value
        outputVolume = session.outputVolume
    }

    deinit {
        observation?.invalidate()
    }
}
