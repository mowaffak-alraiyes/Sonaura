//
//  SplashView.swift
//  Sonaura
//
//  Created for Sonaura app
//

import SwiftUI

struct SplashView: View {
    @State private var isAnimating = false
    @State private var opacity: Double = 1.0
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            // White background (maintains brand consistency in dark mode)
            Color.white
                .ignoresSafeArea()
            
            // App icon centered
            VStack {
                Spacer()
                
                // App Icon - Gradient Circle (matching app branding)
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SonauraColor.accent, SonauraColor.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.blue.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                }
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .opacity(opacity)
                .animation(
                    Animation.easeInOut(duration: 0.6)
                        .repeatCount(2, autoreverses: true),
                    value: isAnimating
                )
                
                Spacer()
            }
        }
        .onAppear {
            startAnimation()
        }
    }
    
    private func startAnimation() {
        // Start pulse animation
        isAnimating = true
        
        // After 1.2 seconds, fade out and transition
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                opacity = 0.0
            }
            
            // Transition to ContentView after fade completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isPresented = false
            }
        }
    }
}

#Preview {
    SplashView(isPresented: .constant(true))
}

