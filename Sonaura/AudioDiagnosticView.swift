//
//  AudioDiagnosticView.swift
//  Sonaura
//
//  Diagnostic tool to identify channel isolation issues
//

import SwiftUI
import AVFoundation

struct AudioDiagnosticView: View {
    @State private var diagnosticResults: [String] = []
    @State private var isTestingLeft = false
    @State private var isTestingRight = false
    
    private let audioSession = AVAudioSession.sharedInstance()
    private let toneGen = ToneGenerator()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Audio Channel Diagnostic")
                    .font(.title.bold())
                    .padding(.bottom)
                
                // Critical Settings Check
                VStack(alignment: .leading, spacing: 12) {
                    Text("⚠️ CRITICAL SETTINGS TO CHECK:")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    SettingCheckItem(
                        title: "Spatial Audio",
                        location: "Settings → Bluetooth → [AirPods]",
                        required: "OFF",
                        importance: .critical
                    )
                    
                    SettingCheckItem(
                        title: "Mono Audio",
                        location: "Settings → Accessibility → Audio/Visual",
                        required: "OFF",
                        importance: .critical
                    )
                    
                    SettingCheckItem(
                        title: "Balance",
                        location: "Settings → Accessibility → Audio/Visual",
                        required: "Centered",
                        importance: .warning
                    )
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
                
                // System Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Information")
                        .font(.headline)
                    
                    DiagnosticRow(label: "Output Channels", value: "\(audioSession.outputNumberOfChannels)")
                    DiagnosticRow(label: "Sample Rate", value: "\(audioSession.sampleRate) Hz")
                    DiagnosticRow(label: "Current Route", value: getCurrentRoute())
                    DiagnosticRow(label: "Headphones", value: areHeadphonesConnected() ? "✅ Connected" : "❌ Not Connected")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Test Buttons
                VStack(spacing: 16) {
                    Text("Channel Isolation Test")
                        .font(.headline)
                    
                    Text("Listen carefully - sound should ONLY play in ONE ear")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button(action: { testLeftChannel() }) {
                        HStack {
                            Image(systemName: "speaker.wave.1.fill")
                            Text("Test LEFT Ear Only")
                            Spacer()
                            if isTestingLeft {
                                ProgressView()
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTestingLeft || isTestingRight)
                    
                    Button(action: { testRightChannel() }) {
                        HStack {
                            Image(systemName: "speaker.wave.1.fill")
                            Text("Test RIGHT Ear Only")
                            Spacer()
                            if isTestingRight {
                                ProgressView()
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isTestingLeft || isTestingRight)
                }
                .padding()
                
                // Diagnostic Results
                if !diagnosticResults.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Console Output")
                            .font(.headline)
                        
                        ForEach(diagnosticResults, id: \.self) { result in
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.systemGray5))
                                .cornerRadius(4)
                        }
                    }
                    .padding()
                }
                
                // Instructions
                VStack(alignment: .leading, spacing: 12) {
                    Text("What Should Happen:")
                        .font(.headline)
                    
                    Text("• LEFT test: Sound ONLY in left headphone")
                    Text("• RIGHT test: Sound ONLY in right headphone")
                    Text("• If you hear in BOTH ears, check settings above")
                    
                    Text("\nIf Still Not Working:")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("1. Turn OFF Spatial Audio in Bluetooth settings")
                    Text("2. Turn OFF Mono Audio in Accessibility")
                    Text("3. Disconnect and reconnect headphones")
                    Text("4. Restart the app")
                    Text("5. Try different headphones (wired works best)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Audio Diagnostic")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func testLeftChannel() {
        isTestingLeft = true
        diagnosticResults.removeAll()
        diagnosticResults.append("🎵 Testing LEFT channel...")
        diagnosticResults.append("Expected: Sound ONLY in LEFT ear")
        
        toneGen.playCalibrated(
            frequency: 1000,
            levelDB: 40,
            ear: .left,
            duration: 1.0,
            airPodsModel: .airPodsPro
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTestingLeft = false
            diagnosticResults.append("✅ Test complete")
            diagnosticResults.append("Did you hear sound ONLY in LEFT ear?")
        }
    }
    
    private func testRightChannel() {
        isTestingRight = true
        diagnosticResults.removeAll()
        diagnosticResults.append("🎵 Testing RIGHT channel...")
        diagnosticResults.append("Expected: Sound ONLY in RIGHT ear")
        
        toneGen.playCalibrated(
            frequency: 1000,
            levelDB: 40,
            ear: .right,
            duration: 1.0,
            airPodsModel: .airPodsPro
        )
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isTestingRight = false
            diagnosticResults.append("✅ Test complete")
            diagnosticResults.append("Did you hear sound ONLY in RIGHT ear?")
        }
    }
    
    private func getCurrentRoute() -> String {
        let route = audioSession.currentRoute
        guard let output = route.outputs.first else {
            return "No Output"
        }
        return output.portName
    }
    
    private func areHeadphonesConnected() -> Bool {
        let route = audioSession.currentRoute
        guard let output = route.outputs.first else { return false }
        
        switch output.portType {
        case .headphones, .headsetMic, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return true
        default:
            return false
        }
    }
}

struct SettingCheckItem: View {
    let title: String
    let location: String
    let required: String
    let importance: Importance
    
    enum Importance {
        case critical, warning
        
        var color: Color {
            switch self {
            case .critical: return .red
            case .warning: return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .critical: return "exclamationmark.triangle.fill"
            case .warning: return "exclamationmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: importance.icon)
                .foregroundColor(importance.color)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Required: \(required)")
                    .font(.caption)
                    .foregroundColor(importance.color)
            }
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .bold()
        }
        .font(.caption)
    }
}

#Preview {
    NavigationStack {
        AudioDiagnosticView()
    }
}
