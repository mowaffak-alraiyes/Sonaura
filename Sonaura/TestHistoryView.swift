import SwiftUI

/// View for browsing and managing past hearing test results
struct TestHistoryView: View {
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var selectedSession: StoredHearingTestSession?
    @State private var showingDeleteAlert = false
    @State private var sessionToDelete: StoredHearingTestSession?
    @State private var showingStorageInfo = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                if dataManager.isLoading {
                    ProgressView("Loading test history...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dataManager.testSessions.isEmpty {
                    emptyStateView
                } else {
                    testHistoryList
                }
            }
            .navigationTitle("Test History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(action: { showingStorageInfo = true }) {
                            Label("Storage Info", systemImage: "info.circle")
                        }
                        
                        if !dataManager.testSessions.isEmpty {
                            Button(role: .destructive, action: { showingDeleteAlert = true }) {
                                Label("Delete All Tests", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $selectedSession) { session in
                TestResultDetailView(session: session, dataManager: dataManager)
            }
            .alert("Delete All Tests", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    dataManager.deleteAllTestSessions()
                }
            } message: {
                Text("This will permanently delete all stored test results. This action cannot be undone.")
            }
            .sheet(isPresented: $showingStorageInfo) {
                StorageInfoView(dataManager: dataManager)
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 80))
                .foregroundStyle(accentGradient)
            
            VStack(spacing: 12) {
                Text("No Test History")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("Complete your first Sonaura hearing test to see your results and track changes over time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(action: { /* Navigate to test */ }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Start Your First Test")
                }
                .font(.headline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(accentGradient)
                .clipShape(Capsule())
            }
        }
    }
    
    private var testHistoryList: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(dataManager.testSessions) { session in
                    TestHistoryRow(
                        session: session,
                        onTap: {
                            selectedSession = session
                        },
                        onDelete: {
                            sessionToDelete = session
                            showingDeleteAlert = true
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .alert("Delete Test", isPresented: .constant(sessionToDelete != nil)) {
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
            Button("Delete", role: .destructive) {
                if let session = sessionToDelete {
                    dataManager.deleteTestSession(session)
                }
                sessionToDelete = nil
            }
        } message: {
            Text("This will permanently delete this test result.")
        }
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Row view for individual test history entries
struct TestHistoryRow: View {
    let session: StoredHearingTestSession
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with date, duration, and delete button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.dateString)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    Text("Duration: \(Int(session.duration / 60)) minutes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Delete button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .font(.subheadline)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            
            // Ear summaries with colored bars (matching results page style)
            HStack(spacing: 16) {
                // Right ear summary with colored bar
                if let rightPTA = session.pureToneAverage(ear: .right) {
                    let rightClassification = session.overallClassification(ear: .right)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(classificationColor(rightClassification).opacity(0.3))
                            .frame(width: 4, height: 60)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Right Ear")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(Int(rightPTA)) dB HL")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(accentGradient)
                            Text(rightClassification.rawValue)
                                .font(.caption)
                                .foregroundStyle(classificationColor(rightClassification))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        Color(.systemGray6).opacity(0.3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Left ear summary with colored bar
                if let leftPTA = session.pureToneAverage(ear: .left) {
                    let leftClassification = session.overallClassification(ear: .left)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(classificationColor(leftClassification).opacity(0.3))
                            .frame(width: 4, height: 60)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Left Ear")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text("\(Int(leftPTA)) dB HL")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(accentGradient)
                            Text(leftClassification.rawValue)
                                .font(.caption)
                                .foregroundStyle(classificationColor(leftClassification))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(
                        Color(.systemGray6).opacity(0.3)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            
            // Device info
            HStack {
                Image(systemName: "headphones")
                    .foregroundStyle(accentGradient)
                    .font(.caption)
                Text(session.deviceModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                
                // View details button
                Button(action: onTap) {
                    HStack(spacing: 4) {
                        Text("View Details")
                            .font(.caption.weight(.medium))
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(accentGradient)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
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
}

/// Detailed view for individual test results
struct TestResultDetailView: View {
    let session: StoredHearingTestSession
    let dataManager: HearingTestDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingTooltip: String? = nil
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    if let hearingSession = session.toHearingTestSession() {
                        // Key Takeaways Summary Card
                        keyTakeawaysCard(session: hearingSession)
                        
                        // Summary cards (matching results page style)
                        ForEach([TestEar.right, TestEar.left], id: \.self) { ear in
                            earSummaryCard(session: hearingSession, ear: ear)
                        }
                        
                        // Action buttons
                        VStack(spacing: 16) {
                            Button(action: exportPDF) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export PDF Report")
                                }
                                .font(.headline.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(accentGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 20)
            }
            .navigationTitle(session.dateString)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive, action: {
                        // Delete this test session
                        dataManager.deleteTestSession(session)
                        dismiss()
                    }) {
                        Label("Delete", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Key Takeaways Card
    
    private func keyTakeawaysCard(session: HearingTestSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text("Key Takeaways")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
            
            let rightPTA = session.pureToneAverage(ear: .right)
            let leftPTA = session.pureToneAverage(ear: .left)
            let rightClassification = session.overallClassification(ear: .right)
            let leftClassification = session.overallClassification(ear: .left)
            
            VStack(alignment: .leading, spacing: 12) {
                if let pta = rightPTA, let leftPTA = leftPTA {
                    takeawayItem(
                        icon: "waveform",
                        text: "Overall hearing: \(rightClassification.rawValue) (Right: \(Int(pta)) dB HL, Left: \(Int(leftPTA)) dB HL)"
                    )
                }
                
                if rightClassification == .normal || leftClassification == .normal {
                    takeawayItem(
                        icon: "checkmark.circle.fill",
                        text: "Your hearing is within normal range. Continue protecting your hearing with safe listening practices."
                    )
                } else if rightClassification == .mild || leftClassification == .mild {
                    takeawayItem(
                        icon: "exclamationmark.triangle.fill",
                        text: "Mild hearing loss detected. Consider consulting an audiologist and protecting your hearing."
                    )
                } else {
                    takeawayItem(
                        icon: "exclamationmark.triangle.fill",
                        text: "Hearing loss detected. We recommend consulting an audiologist for a comprehensive evaluation."
                    )
                }
                
                takeawayItem(
                    icon: "info.circle.fill",
                    text: "This is a screening test, not a diagnostic evaluation. For accurate diagnosis, see a licensed audiologist."
                )
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 24)
    }
    
    private func takeawayItem(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(accentGradient)
                .font(.subheadline)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private func earSummaryCard(session: HearingTestSession, ear: TestEar) -> some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        HStack(spacing: 6) {
                            Text("Pure Tone Average (PTA)")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Button(action: {
                                showingTooltip = showingTooltip == "PTA" ? nil : "PTA"
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(accentGradient)
                                    .font(.caption)
                            }
                        }
                        
                        HStack(spacing: 6) {
                            Text("\(Int(pta)) dB HL")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(accentGradient)
                            Button(action: {
                                showingTooltip = showingTooltip == "dBHL" ? nil : "dBHL"
                            }) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(accentGradient)
                                    .font(.caption)
                            }
                        }
                        
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
                        
                        if showingTooltip == "PTA" {
                            tooltipView(text: "Pure Tone Average (PTA) is the average of your hearing thresholds at 500, 1000, 2000, and 4000 Hz. This is the standard metric audiologists use to assess overall hearing ability.")
                        }
                        
                        if showingTooltip == "dBHL" {
                            tooltipView(text: "dB HL (Decibels Hearing Level) measures how loud a sound needs to be for you to hear it. Lower numbers = better hearing. 0-25 dB HL is normal, 26-40 dB HL is mild loss.")
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
            
            // Frequency-by-frequency breakdown with percentiles (matching results page)
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
        .padding(.horizontal, 24)
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
    
    private func tooltipView(text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
            .background(
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.top, 4)
            .transition(.opacity.combined(with: .scale))
    }
    
    private func exportPDF() {
        guard let hearingSession = session.toHearingTestSession() else { return }
        
        let pdfData = PDFExporter.generatePDF(for: hearingSession)
        let filename = PDFExporter.generateFilename(for: hearingSession)
        
        if let url = PDFExporter.savePDFToDocuments(pdfData, filename: filename) {
            // Present share sheet
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
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
}

/// Storage information view
struct StorageInfoView: View {
    let dataManager: HearingTestDataManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 60))
                        .foregroundStyle(accentGradient)
                    
                    Text("Storage Information")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 40)
                
                let storageInfo = dataManager.getStorageInfo()
                
                VStack(spacing: 16) {
                    StorageInfoRow(title: "Total Tests", value: "\(storageInfo.count)")
                    StorageInfoRow(title: "Storage Used", value: storageInfo.totalSize)
                    StorageInfoRow(title: "Average per Test", value: storageInfo.count > 0 ? ByteCountFormatter.string(fromByteCount: Int64(storageInfo.totalSize.replacingOccurrences(of: " KB", with: "").replacingOccurrences(of: " MB", with: "")) ?? 0 / Int64(storageInfo.count), countStyle: .file) : "0 KB")
                }
                .padding(.horizontal, 24)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.headline.weight(.medium))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(accentGradient)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("Storage")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct StorageInfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(accentGradient)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview {
    TestHistoryView()
}


