import Foundation
import CoreBluetooth
import Combine

/// Tracks CoreBluetooth authorization and power state, and can nudge the system to present the Bluetooth permission prompt.
/// Note: Bluetooth permission is not required just to detect the audio route, but you requested it for connected device access.
final class BluetoothAccessManager: NSObject, ObservableObject, CBCentralManagerDelegate {

    @Published var authorization: CBManagerAuthorization
    @Published var isPoweredOn: Bool = false

    private var central: CBCentralManager?

    override init() {
        if #available(iOS 13.0, *) {
            authorization = CBCentralManager.authorization
        } else {
            authorization = .allowedAlways
        }
        super.init()
        // Initialize immediately to encourage the system to present the permission prompt when needed.
        ensureCentral()
    }

    /// Ensure the central manager exists (creating it may trigger the permission flow on first use).
    func ensureCentral() {
        if central == nil {
            central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
        }
    }

    /// Gently request access by ensuring the central is created.
    func requestAccess() {
        ensureCentral()
        // No explicit request API; the system prompts automatically when appropriate.
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isPoweredOn = central.state == .poweredOn
        if #available(iOS 13.0, *) {
            authorization = type(of: central).authorization
        } else {
            authorization = .allowedAlways
        }
    }

    var isAuthorized: Bool {
        if #available(iOS 13.0, *) {
            return authorization == .allowedAlways
        } else {
            return true
        }
    }

    /// Bluetooth ready means authorized and radio powered on.
    var isReady: Bool {
        isAuthorized && isPoweredOn
    }

    var authorizationDescription: String {
        if #available(iOS 13.0, *) {
            switch authorization {
            case .allowedAlways: return "Allowed"
            case .denied: return "Denied"
            case .restricted: return "Restricted"
            case .notDetermined: return "Not Determined"
            @unknown default: return "Unknown"
            }
        } else {
            return "Allowed"
        }
    }
}
