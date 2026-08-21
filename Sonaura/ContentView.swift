//
//  ContentView.swift
//  Sonaura
//
//  Created by Mo Alraiyes on 10/2/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var coordinator: HearingTestCoordinator
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var showingTestPreparation = false
    @State private var selectedTab = 0
    @State private var hasRequestedBluetoothAccess = false
    
    // Convenience access to view model through coordinator
    private var vm: HearingTestViewModel {
        coordinator.viewModel
    }
    
    // Pre-computed gradients for better performance
    /// The single accent, replacing the stock blue→purple gradient that was
    /// previously declared independently in two places in this file. See
    /// docs/design-system.md §1: one saturated color in the whole system.
    private let accentGradient = LinearGradient(
        colors: [SonauraColor.accent, SonauraColor.accent],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    private let backgroundGradient = LinearGradient(
        colors: [
            Color(.systemBackground),
            Color(.systemBackground).opacity(0.95)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        TabView(selection: $selectedTab) {
            // Main Test Tab
            NavigationStack {
                ZStack {
                    gradientBackground

                    VStack(spacing: 24) {
                        if vm.isRunning {
                            testInProgressView
                                .transition(.opacity.combined(with: .scale))
                        } else if let session = vm.testSession {
                            resultsView(session: session)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        } else {
                            mainTestView
                                .transition(.opacity)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: vm.isRunning)
                    .animation(.easeInOut(duration: 0.3), value: vm.testSession != nil)
                }
                .navigationTitle("Sonaura")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        connectionChip
                    }
                }
            }
            .tabItem {
                Image(systemName: "waveform")
                Text("Check")
            }
            .tag(0)
            
            // Test History Tab
            TestHistoryView()
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("History")
                }
                .tag(1)
            
            // Trends Tab
            TrendTrackingView()
                .tabItem {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Trends")
                }
                .tag(2)
            
            // Settings Tab
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(3)
        }
        .onChange(of: vm.testSession) { _, newSession in
            // Performance: Save on background thread to avoid blocking UI
            if let session = newSession {
                Task.detached(priority: .utility) {
                    await MainActor.run {
                        dataManager.saveTestSession(session)
                    }
                }
            }
        }
        .onAppear {
            // Performance: Only run once
            requestBluetoothAuthorizationIfNeeded()
        }
    }
    
    // MARK: - Background

    private var gradientBackground: some View {
        backgroundGradient
            .ignoresSafeArea()
    }
    
    private func requestBluetoothAuthorizationIfNeeded() {
        guard !hasRequestedBluetoothAccess else { return }
        hasRequestedBluetoothAccess = true
        coordinator.bluetoothManager.requestAccess()
    }

    // MARK: - Main Test View

    private var mainTestView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(accentGradient)
                
                VStack(spacing: 12) {
                    Text("Sound Check")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("A gentle, repeatable way to notice how your hearing changes over time.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
            }
            
            // Quick start button
            Button(action: {
                // Performance: Animate transition smoothly
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingTestPreparation = true
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start a Sound Check")
                }
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 40)
            
            // Features preview
            VStack(alignment: .leading, spacing: 16) {
                FeaturePreviewItem(icon: "chart.line.uptrend.xyaxis", text: "Builds a trend across check-ins")
                FeaturePreviewItem(icon: "person.2", text: "Context for your age group")
                FeaturePreviewItem(icon: "headphones", text: "Calibrated for AirPods")
                FeaturePreviewItem(icon: "shield.fill", text: "Safe, brief tones — never loud")
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .sheet(isPresented: $showingTestPreparation) {
            TestPreparationFlow()
        }
    }

    // MARK: - Test In Progress View

    private var testInProgressView: some View {
        VStack(spacing: 32) {
            // Progress
            VStack(spacing: 12) {
                ProgressView(value: vm.progress)
                    .tint(SonauraColor.accent)
                    .scaleEffect(y: 2)
                Text("Test \(vm.currentStepIndex + 1) of \(vm.steps.count)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let step = vm.currentStep {
                VStack(spacing: 32) {
                    // Title: "Right Ear — 1,000 Hz"
                    VStack(spacing: 8) {
                        Text("\(step.ear.displayName) — \(step.frequencyHz.formatted()) Hz")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        // Instructions
                        Text(vm.currentInstructions)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                        
                    }
                    
                    // Play Sound Button
                    Button(action: { vm.playSound() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                            Text("Play Sound")
                                .font(.title2.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            LinearGradient(
                                colors: [SonauraColor.accent, SonauraColor.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(vm.hasPlayedCurrentTone && vm.isWaitingForResponse)
                    .opacity((vm.hasPlayedCurrentTone && vm.isWaitingForResponse) ? 0.6 : 1.0)
                    
                    // Response Buttons: Yes / No (only enabled after tone is played)
                    if vm.hasPlayedCurrentTone {
                        HStack(spacing: 20) {
                            // No button
                            Button(action: { 
                                // Performance: Animate button press
                                withAnimation(.easeOut(duration: 0.2)) {
                                    vm.recordResponse(heard: false)
                                }
                            }) {
                                Text("No")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(SonauraColor.text)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    // Neutral and equal-weight, deliberately.
                                    // These were Color.red / Color.green, which
                                    // made a raw yes/no *input* look like a
                                    // pass/fail *verdict* — the exact framing
                                    // the v2 reframe retires. Not hearing a
                                    // quiet tone is not a failure. Color now
                                    // belongs to the result, never the input.
                                    .background(SonauraColor.surfaceElevated)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .strokeBorder(SonauraColor.border, lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(!vm.isWaitingForResponse)
                            
                            // Yes button
                            Button(action: { 
                                // Performance: Animate button press
                                withAnimation(.easeOut(duration: 0.2)) {
                                    vm.recordResponse(heard: true)
                                }
                            }) {
                                Text("Yes")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(SonauraColor.background)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    // The affirmative gets the accent because
                                    // it is the primary action, not because it
                                    // is the "good" answer.
                                    .background(SonauraColor.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(!vm.isWaitingForResponse)
                        }
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.hasPlayedCurrentTone)
                    }
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    // MARK: - Results View

    private func resultsView(session: HearingTestSession) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Text("Test Complete!")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Your Sonaura Test results are ready")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // "What This Means" collapsible section
                whatThisMeansSection
                
                // Summary cards
                ForEach([TestEar.right, TestEar.left], id: \.self) { ear in
                    earResultCard(session: session, ear: ear)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    Button(action: { vm.restart() }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Take Another Test")
                        }
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    Button(action: { exportPDF(for: session) }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Results")
                        }
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(accentGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Connection Chip

    private var connectionChip: some View {
        Button(action: {
            vm.routeMonitor.refresh()
        }) {
            HStack(spacing: 8) {
                Image(systemName: vm.routeMonitor.isHeadphoneLikeConnected ? "earbuds" : "speaker.wave.2.fill")
                    .foregroundStyle(vm.routeMonitor.isHeadphoneLikeConnected ? .green : .orange)
                Text(vm.routeMonitor.routeDescription)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
    }
    
    // MARK: - Helper Views
    
    private func earResultCard(session: HearingTestSession, ear: TestEar) -> some View {
        // Performance: Pre-compute heavy calculations once
        let cardData = EarResultCardData(session: session, ear: ear)
        
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: ear == .right ? "ear.trianglebadge.exclamationmark" : "ear.badge.checkmark")
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text(ear.displayName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            // Pure Tone Average with percentile and colored bar
            if let cardData = cardData, let pta = cardData.pta {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(classificationColor(cardData.ptaClassification).opacity(0.3))
                        .frame(width: 4, height: 60)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pure Tone Average (PTA)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("\(Int(pta)) dB HL")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(accentGradient)
                        
                        // PTA interpretation
                        Text(interpretPTA(pta))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                        
                        // PTA Percentile (pre-computed)
                        if let avgPercentile = cardData.avgPercentile, let label = cardData.percentileLabel {
                            percentileBadge(percentile: avgPercentile, label: label)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    Color(.systemGray6).opacity(0.3)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            // Overall Classification with colored bar
            let classification = session.overallClassification(ear: ear)
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(classificationColor(classification).opacity(0.3))
                    .frame(width: 4, height: 50)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(classification.rawValue)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text(classification.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Color(.systemGray6).opacity(0.3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            Divider()
            
            // Frequency-by-frequency breakdown with percentiles
            if let cardData = cardData {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(accentGradient)
                            .font(.headline)
                        Text("Frequency Breakdown")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    // CRITICAL: Always show explanatory note about screening resolution
                    // Percentiles are estimates based on threshold ranges, not exact measurements
                    VStack(alignment: .leading, spacing: 4) {
                        Text("📊 Percentile Estimates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Text("Percentiles shown are estimates based on screening threshold ranges, not exact measurements. The test uses 4-level screening (15, 25, 40, 55 dB HL) which brackets your threshold within a range:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("• ≤15 dB HL → uses 7.5 dB HL (midpoint of 0-15 range)")
                            Text("• 15-25 dB HL → uses 20 dB HL (midpoint of 15-25 range)")
                            Text("• 25-40 dB HL → uses 32.5 dB HL (midpoint of 25-40 range)")
                            Text("• 40-55 dB HL → uses 47.5 dB HL (midpoint of 40-55 range)")
                            Text("• ≥55 dB HL → uses 70 dB HL (conservative estimate)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        
                        if cardData.hasHighThresholds {
                            Text("Note: Thresholds marked '≥55 dB HL' are estimates. Your actual threshold may be higher since the screening test stops at 55 dB HL.")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        Color(.systemGray6).opacity(0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 8)
                    
                    // Performance: Use pre-sorted results
                    ForEach(cardData.sortedResults) { result in
                        frequencyResultRow(result: result, age: cardData.age, gender: cardData.gender)
                    }
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func frequencyResultRow(result: ThresholdResult, age: Int, gender: ISO7029Calculator.Gender) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Colored bar based on category
            if let category = result.category {
                RoundedRectangle(cornerRadius: 4)
                    .fill(categoryColor(category).opacity(0.3))
                    .frame(width: 4, height: 40)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4, height: 40)
            }
            
            // Frequency
            Text("\(result.frequencyHz) Hz")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .leading)
            
            // Category/Threshold - constrained width to prevent pushing percentile badge off screen
            Group {
                if let category = result.category {
                    // Descriptive label, not the clinical dB band (PRD.md §3.1).
                    Text(category.gentleLabel)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Text("\(Int(result.thresholdDB)) dB HL")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0.5) // Lower priority than percentile badge
            
            // Frequency-based percentile (based on category range, not specific dB)
            Group {
                if let category = result.category {
                    frequencyPercentileBadge(category: category, frequency: result.frequencyHz, age: age, gender: gender)
                } else {
                    // Fallback to dB-based if no category
                    let percentile = ISO7029Calculator.percentile(
                        measuredThreshold: result.thresholdDB,
                        age: age,
                        frequency: result.frequencyHz,
                        gender: gender
                    )
                    percentileBadge(percentile: percentile, label: nil)
                }
            }
            .layoutPriority(1.0) // Higher priority - ensure badge is always visible
            .fixedSize(horizontal: true, vertical: false) // Prevent badge from being compressed
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Color(.systemGray6).opacity(0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    /// Two tones, not a four-color severity ramp. green→yellow→orange→red is
    /// the pass/fail vocabulary the v2 reframe retires (PRD.md §3.4,
    /// docs/design-system.md §1) — a routine "softer response" should not
    /// sit on the same visual ramp as a result that genuinely warrants a
    /// checkup. See `SonauraResultTone`.
    private func categoryColor(_ category: ThresholdCategory) -> Color {
        category.gentleTone == "attention" ? SonauraColor.worthALook : SonauraColor.steady
    }
    
    /// Calculate frequency-based percentile range from category
    /// This shows percentiles based on the frequency's expected performance range, not specific dB
    private func frequencyPercentileBadge(
        category: ThresholdCategory,
        frequency: Int,
        age: Int,
        gender: ISO7029Calculator.Gender
    ) -> some View {
        // Calculate percentile range for the category at this frequency
        let minThreshold = categoryMinThreshold(category)
        let maxThreshold = categoryMaxThreshold(category)
        
        let minPercentile = ISO7029Calculator.percentile(
            measuredThreshold: minThreshold,
            age: age,
            frequency: frequency,
            gender: gender
        )
        let maxPercentile = ISO7029Calculator.percentile(
            measuredThreshold: maxThreshold,
            age: age,
            frequency: frequency,
            gender: gender
        )
        
        // Use the midpoint percentile for display
        let avgPercentile = (minPercentile + maxPercentile) / 2.0
        let isBetter = avgPercentile < 50
        let isWorse = avgPercentile > 50
        
        // Cap range to 15 percentiles maximum
        let rawRange = abs(maxPercentile - minPercentile)
        let cappedMaxPercentile: Double
        if rawRange > 15 {
            // Cap the range to 15 percentiles
            cappedMaxPercentile = minPercentile + 15.0
        } else {
            cappedMaxPercentile = maxPercentile
        }
        
        // Format as range or single value
        // CRITICAL: All percentiles are estimates based on screening threshold ranges, not exact measurements
        let percentileText: String
        let cappedRange = abs(cappedMaxPercentile - minPercentile)
        if cappedRange < 5 {
            // Narrow range, show single estimated value with "~" prefix to indicate estimate
            let displayPercentile = (minPercentile + cappedMaxPercentile) / 2.0
            if displayPercentile >= 99.0 {
                percentileText = "~≤99th"
            } else if displayPercentile > 50 {
                percentileText = "~≤\(Int(displayPercentile.rounded()))th"
            } else if displayPercentile < 50 {
                percentileText = "~Better than \(Int((100 - displayPercentile).rounded()))%"
            } else {
                percentileText = "~50th"
            }
        } else {
            // Show range (capped at 15) with "~" prefix to indicate estimate
            let minRounded = Int(minPercentile.rounded())
            let maxRounded = Int(cappedMaxPercentile.rounded())
            let displayAvg = (minPercentile + cappedMaxPercentile) / 2.0
            if displayAvg >= 99.0 {
                percentileText = "~≤\(minRounded)-\(maxRounded)th"
            } else if displayAvg > 50 {
                percentileText = "~≤\(minRounded)-\(maxRounded)th"
            } else {
                percentileText = "~\(minRounded)-\(maxRounded)th"
            }
        }
        
        // Use category color for badge (matches the colored bar)
        let badgeColor = categoryColor(category)
        
        return Text(percentileText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(badgeColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                badgeColor.opacity(0.15)
            )
            .clipShape(Capsule())
            .help("Percentile estimate based on screening threshold range (\(category.displayName)). Actual threshold may vary within this range.")
    }
    
    private func categoryMinThreshold(_ category: ThresholdCategory) -> Double {
        switch category {
        case .excellentHearing: return 0.0
        case .normalHearing: return 15.0
        case .mildLoss: return 25.0
        case .moderateLoss: return 40.0
        case .moderateSevereOrWorse: return 55.0
        }
    }
    
    private func categoryMaxThreshold(_ category: ThresholdCategory) -> Double {
        switch category {
        case .excellentHearing: return 15.0
        case .normalHearing: return 25.0
        case .mildLoss: return 40.0
        case .moderateLoss: return 55.0
        case .moderateSevereOrWorse: return 90.0 // Conservative upper bound
        }
    }
    
    private func percentileBadge(percentile: Double, label: String?) -> some View {
        let isBetter = percentile < 50
        let isWorse = percentile > 50
        
        // Format percentile with ≤ symbol for "worse than" cases
        // CRITICAL: Add "~" prefix to indicate this is an estimate
        let percentileText: String
        if percentile >= 99.0 {
            percentileText = "~≤99th percentile"
        } else if percentile > 50 {
            percentileText = "~≤\(Int(percentile.rounded()))th percentile"
        } else if percentile < 50 {
            percentileText = "~Better than \(Int((100 - percentile).rounded()))%"
        } else {
            percentileText = "~50th percentile (average)"
        }
        
        // Use blue/purple gradient for worse than average, green for better
        let badgeColor: Color = isBetter ? .green : (isWorse ? .blue : .gray)
        let foregroundStyle: AnyShapeStyle = isBetter ? AnyShapeStyle(Color.green) : (isWorse ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.gray))
        
        return VStack(spacing: 4) {
            Text(percentileText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(foregroundStyle)
            
            if let label = label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            badgeColor.opacity(0.15)
        )
        .clipShape(Capsule())
        .help("Percentile estimate based on screening threshold range. Actual threshold may vary within the category range.")
    }
    
    // MARK: - What This Means Section
    
    @State private var isWhatThisMeansExpanded = false
    
    private var whatThisMeansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isWhatThisMeansExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(accentGradient)
                        .font(.headline)
                    Text("What This Means")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isWhatThisMeansExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            
            if isWhatThisMeansExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    explanationItem(
                        term: "Percentiles",
                        explanation: "Percentiles compare your hearing to others your age and gender. '≤80%' means your hearing is worse than 80% of people your age. Lower percentiles = better hearing."
                    )
                    
                    explanationItem(
                        term: "dB HL (Hearing Level)",
                        explanation: "Decibels Hearing Level measures how loud a sound needs to be for you to hear it. Lower numbers = better hearing. 0-25 dB HL is normal, 26-40 dB HL is mild loss."
                    )
                    
                    explanationItem(
                        term: "PTA (Pure Tone Average)",
                        explanation: "The average of your hearing thresholds at 500, 1000, 2000, and 4000 Hz. This is the standard metric audiologists use to assess overall hearing."
                    )
                    
                    // PTA Range Chart
                    ptaRangeChart
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    
    private func explanationItem(term: String, explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(term)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var ptaRangeChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PTA Range Chart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            
            VStack(alignment: .leading, spacing: 8) {
                ptaRangeRow(range: "0-15 dB HL", label: "Normal", color: .green)
                ptaRangeRow(range: "16-25 dB HL", label: "Normal Variation", color: .cyan)
                ptaRangeRow(range: "26-40 dB HL", label: "Mild Loss", color: .yellow)
                ptaRangeRow(range: "41-55 dB HL", label: "Moderate Loss", color: .orange)
                ptaRangeRow(range: "56-70 dB HL", label: "Moderately Severe", color: .red)
                ptaRangeRow(range: "71-90 dB HL", label: "Severe Loss", color: .red)
                ptaRangeRow(range: ">90 dB HL", label: "Profound Loss", color: .purple)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func ptaRangeRow(range: String, label: String, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.3))
                .frame(width: 4, height: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(range)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func interpretPTA(_ pta: Double) -> String {
        switch pta {
        case ..<16:
            return "Normal hearing. You can hear most sounds clearly."
        case 16..<26:
            return "Normal variation. Slight difficulty with very soft sounds."
        case 26..<41:
            return "Mild loss. Difficulty hearing soft speech or in noisy places."
        case 41..<56:
            return "Moderate loss. Difficulty with normal conversation."
        case 56..<71:
            return "Moderately severe loss. Most speech is difficult without amplification."
        case 71..<91:
            return "Severe loss. Hearing aids are essential for communication."
        default:
            return "Profound loss. Consider cochlear implants or other interventions."
        }
    }
    
    private func classificationColor(_ classification: HearingClassification) -> Color {
        switch classification {
        case .exceptional, .normal:
            return .green
        case .normalVariation:
            return .cyan
        case .mild:
            return .yellow
        case .moderate:
            return .orange
        case .moderatelySevere, .severe:
            return .red
        case .profound:
            return .purple
        }
    }
    
    // MARK: - Export Functionality
    
    private func exportPDF(for session: HearingTestSession) {
        let pdfData = PDFExporter.generatePDF(for: session)
        let filename = PDFExporter.generateFilename(for: session)
        
        if let url = PDFExporter.savePDFToDocuments(pdfData, filename: filename) {
            // Present share sheet
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
}

// MARK: - Performance: Cached Computations

/// Cached computation data for ear result card to avoid recalculating on every render
/// Performance: Pre-computes heavy calculations once instead of in view body
private struct EarResultCardData {
    let pta: Double?
    let ptaClassification: HearingClassification
    let avgPercentile: Double?
    let percentileLabel: String?
    let hasHighThresholds: Bool
    let hasNormalThresholds: Bool
    let sortedResults: [ThresholdResult]
    let age: Int
    let gender: ISO7029Calculator.Gender
    
    init?(session: HearingTestSession, ear: TestEar) {
        guard let age = session.userAge,
              let gender = session.userGender else {
            return nil
        }
        
        self.age = age
        self.gender = gender
        
        // Pre-compute PTA
        self.pta = session.pureToneAverage(ear: ear)
        self.ptaClassification = self.pta.map { ISO7029Calculator.classify(thresholdDB: $0) } ?? .normal
        
        // Pre-compute PTA percentiles
        let ptaFrequencies = [500, 1000, 2000, 4000]
        let earResults = session.results(for: ear)
        let ptaResults = earResults.filter { ptaFrequencies.contains($0.frequencyHz) }
        let ptaPercentiles = ptaResults.map { result -> Double in
            ISO7029Calculator.percentile(
                measuredThreshold: result.thresholdDB,
                age: age,
                frequency: result.frequencyHz,
                gender: gender
            )
        }
        
        if !ptaPercentiles.isEmpty {
            self.avgPercentile = ptaPercentiles.reduce(0, +) / Double(ptaPercentiles.count)
            let genderLabel = gender == .male ? "males" : "females"
            self.percentileLabel = "vs \(age)-year-old \(genderLabel)"
        } else {
            self.avgPercentile = nil
            self.percentileLabel = nil
        }
        
        // Pre-compute flags
        self.hasHighThresholds = earResults.contains { $0.category == .moderateSevereOrWorse }
        self.hasNormalThresholds = earResults.contains {
            $0.category == .excellentHearing || $0.category == .normalHearing
        }
        
        // Pre-sort results
        self.sortedResults = earResults.sorted { $0.frequencyHz < $1.frequencyHz }
    }
}

// MARK: - Helper Views

struct FeaturePreviewItem: View {
    let icon: String
    let text: String
    
    // Pre-computed gradient for better performance
    /// The single accent, replacing the stock blue→purple gradient that was
    /// previously declared independently in two places in this file. See
    /// docs/design-system.md §1: one saturated color in the whole system.
    private let accentGradient = LinearGradient(
        colors: [SonauraColor.accent, SonauraColor.accent],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(accentGradient)
                .font(.title2)
                .frame(width: 32)
            
            Text(text)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ContentView()
        .environmentObject(HearingTestCoordinator())
}
