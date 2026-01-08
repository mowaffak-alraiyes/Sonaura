//
//  SonauraApp.swift
//  Sonaura
//
//  Created by Mo Alraiyes on 10/2/25.
//

import SwiftUI
import SwiftData

@main
struct SonauraApp: App {
    let modelContainer: ModelContainer
    @StateObject private var coordinator = HearingTestCoordinator()
    @State private var showSplash = true
    
    init() {
        do {
            let schema = Schema([StoredHearingTestSession.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    SplashView(isPresented: $showSplash)
                        .transition(.opacity)
                } else {
                    ContentView()
                        .environmentObject(coordinator)
                        .modelContainer(modelContainer)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSplash)
            .onAppear {
                // Request Bluetooth authorization when app launches
                coordinator.bluetoothManager.requestAccess()
            }
        }
    }
}
