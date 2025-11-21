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
    private let accentGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
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
                        } else if let session = vm.testSession {
                            resultsView(session: session)
                        } else {
                            mainTestView
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text("Test")
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
            // Save test session when completed
            if let session = newSession {
                dataManager.saveTestSession(session)
            }
        }
        .onAppear {
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
                    Text("Sonaura Test")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Measure your hearing sensitivity using clinically-validated methods")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
            }
            
            // Quick start button
            Button(action: { showingTestPreparation = true }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Sonaura Test")
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
                FeaturePreviewItem(icon: "checkmark.shield.fill", text: "Clinically-validated Hughson-Westlake method")
                FeaturePreviewItem(icon: "chart.line.uptrend.xyaxis", text: "Age-matched hearing comparisons")
                FeaturePreviewItem(icon: "headphones", text: "Calibrated for AirPods")
                FeaturePreviewItem(icon: "shield.fill", text: "Safe listening guidelines")
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
                    .tint(Color.blue)
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
                                colors: [Color.blue, Color.purple],
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
                            Button(action: { vm.recordResponse(heard: false) }) {
                                Text("No")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(!vm.isWaitingForResponse)
                            
                            // Yes button
                            Button(action: { vm.recordResponse(heard: true) }) {
                                Text("Yes")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Color.green)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            .disabled(!vm.isWaitingForResponse)
                        }
                        .padding(.top, 8)
                        .transition(.opacity.combined(with: .scale))
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
        VStack(alignment: .leading, spacing: 20) {
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
            if let pta = session.pureToneAverage(ear: ear),
               let age = session.userAge,
               let gender = session.userGender {
                let ptaClassification = ISO7029Calculator.classify(thresholdDB: pta)
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(classificationColor(ptaClassification).opacity(0.3))
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
                        
                        // PTA Percentile - average percentile across PTA frequencies
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
                            let avgPercentile = ptaPercentiles.reduce(0, +) / Double(ptaPercentiles.count)
                            let genderLabel = gender == .male ? "males" : "females"
                            percentileBadge(percentile: avgPercentile, label: "vs \(age)-year-old \(genderLabel)")
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
            if let age = session.userAge, let gender = session.userGender {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(accentGradient)
                            .font(.headline)
                        Text("Frequency Breakdown")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    
                    // Note about threshold estimates
                    let hasHighThresholds = session.results(for: ear).contains { $0.category == .moderateSevereOrWorse }
                    let hasNormalThresholds = session.results(for: ear).contains {
                        $0.category == .excellentHearing || $0.category == .normalHearing
                    }
                    
                    if hasHighThresholds {
                        Text("Note: Thresholds marked '≥55 dB HL' are estimates. Your actual threshold may be higher since the screening test stops at 55 dB HL.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    
                    if hasNormalThresholds {
                        Text("Note: Percentiles are estimates based on screening categories. For '≤15 dB HL', we use 7.5 dB HL (midpoint). For '15-25 dB HL', we use 20 dB HL (midpoint). For young adults, even small differences from 0 dB HL can show higher percentiles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }
                    
                    let earResults = session.results(for: ear).sorted { $0.frequencyHz < $1.frequencyHz }
                    ForEach(earResults) { result in
                        frequencyResultRow(result: result, age: age, gender: gender)
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
        HStack(spacing: 12) {
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
            
            // Category/Threshold
            if let category = result.category {
                Text(category.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            } else {
                Text("\(Int(result.thresholdDB)) dB HL")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            // Frequency-based percentile (based on category range, not specific dB)
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
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            Color(.systemGray6).opacity(0.3)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    private func categoryColor(_ category: ThresholdCategory) -> Color {
        switch category {
        case .excellentHearing, .normalHearing:
            return .green
        case .mildLoss:
            return .yellow
        case .moderateLoss:
            return .orange
        case .moderateSevereOrWorse:
            return .red
        }
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
        let percentileText: String
        let cappedRange = abs(cappedMaxPercentile - minPercentile)
        if cappedRange < 5 {
            // Narrow range, show single value
            let displayPercentile = (minPercentile + cappedMaxPercentile) / 2.0
            if displayPercentile >= 99.0 {
                percentileText = "≤99th"
            } else if displayPercentile > 50 {
                percentileText = "≤\(Int(displayPercentile.rounded()))th"
            } else if displayPercentile < 50 {
                percentileText = "Better than \(Int((100 - displayPercentile).rounded()))%"
            } else {
                percentileText = "50th"
            }
        } else {
            // Show range (capped at 15)
            let minRounded = Int(minPercentile.rounded())
            let maxRounded = Int(cappedMaxPercentile.rounded())
            let displayAvg = (minPercentile + cappedMaxPercentile) / 2.0
            if displayAvg >= 99.0 {
                percentileText = "≤\(minRounded)-\(maxRounded)th"
            } else if displayAvg > 50 {
                percentileText = "≤\(minRounded)-\(maxRounded)th"
            } else {
                percentileText = "\(minRounded)-\(maxRounded)th"
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
        let percentileText: String
        if percentile >= 99.0 {
            percentileText = "≤99th percentile"
        } else if percentile > 50 {
            percentileText = "≤\(Int(percentile.rounded()))th percentile"
        } else if percentile < 50 {
            percentileText = "Better than \(Int((100 - percentile).rounded()))%"
        } else {
            percentileText = "50th percentile (average)"
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

// MARK: - Helper Views

struct FeaturePreviewItem: View {
    let icon: String
    let text: String
    
    // Pre-computed gradient for better performance
    private let accentGradient = LinearGradient(
        colors: [Color.blue, Color.purple],
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
