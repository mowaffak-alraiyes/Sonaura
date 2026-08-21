//
//  TonePlayerExampleView.swift
//  Sonaura
//
//  Example SwiftUI view demonstrating TonePlayer usage
//  with headphone detection and route change handling
//

import SwiftUI
import AVFoundation

struct TonePlayerExampleView: View {
    private let tonePlayer = TonePlayer()
    @State private var isHeadphonesConnected = false
    @State private var currentRoute = "Checking..."
    @State private var showingNoHeadphonesAlert = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Status
            VStack(spacing: 12) {
                Image(systemName: isHeadphonesConnected ? "headphones" : "headphones.badge.exclamationmark")
                    .font(.system(size: 60))
                    .foregroundColor(isHeadphonesConnected ? .green : .orange)
                
                Text(isHeadphonesConnected ? "Headphones Connected" : "No Headphones Detected")
                    .font(.headline)
                
                Text(currentRoute)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Test Buttons
            VStack(spacing: 16) {
                Button(action: {
                    if checkHeadphones() {
                        tonePlayer.playTone(
                            frequency: 1000,
                            duration: 0.5,
                            ear: .left,
                            level: 0.5
                        )
                    }
                }) {
                    Text("Test Left Ear")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isHeadphonesConnected)
                
                Button(action: {
                    if checkHeadphones() {
                        tonePlayer.playTone(
                            frequency: 1000,
                            duration: 0.5,
                            ear: .right,
                            level: 0.5
                        )
                    }
                }) {
                    Text("Test Right Ear")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isHeadphonesConnected)
                
                Button(action: {
                    if checkHeadphones() {
                        tonePlayer.playTone(
                            frequency: 1000,
                            duration: 0.5,
                            ear: .both,
                            level: 0.5
                        )
                    }
                }) {
                    Text("Test Both Ears")
                }
                .buttonStyle(.bordered)
                .disabled(!isHeadphonesConnected)
                
                Button(action: {
                    tonePlayer.stop()
                }) {
                    Text("Stop")
                }
                .buttonStyle(.bordered)
            }
            
            Spacer()
        }
        .padding()
        .navigationTitle("Tone Player Test")
        .onAppear {
            checkHeadphones()
            setupRouteMonitoring()
        }
        .alert("Headphones Required", isPresented: $showingNoHeadphonesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please connect headphones or AirPods before playing tones. This ensures accurate audio delivery to each ear.")
        }
    }
    
    private func checkHeadphones() -> Bool {
        isHeadphonesConnected = tonePlayer.areHeadphonesConnected()
        currentRoute = tonePlayer.getCurrentRoute()
        
        if !isHeadphonesConnected {
            showingNoHeadphonesAlert = true
        }
        
        return isHeadphonesConnected
    }
    
    private func setupRouteMonitoring() {
        // Monitor route changes
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            checkHeadphones()
            print("🔄 Audio route changed: \(tonePlayer.getCurrentRoute())")
        }
    }
}

#Preview {
    NavigationStack {
        TonePlayerExampleView()
    }
}

