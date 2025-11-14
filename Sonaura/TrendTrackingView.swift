import SwiftUI
import Charts

/// View for tracking hearing changes over time
struct TrendTrackingView: View {
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var selectedEar: TestEar = .right
    @State private var selectedMetric: TrendMetric = .pta
    
    enum TrendMetric: String, CaseIterable {
        case pta = "Pure Tone Average"
        case classification = "Classification"
        
        var icon: String {
            switch self {
            case .pta: return "waveform"
            case .classification: return "chart.bar"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                if dataManager.isLoading {
                    ProgressView("Loading trend data...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if dataManager.testSessions.count < 2 {
                    insufficientDataView
                } else {
                    trendContentView
                }
            }
            .navigationTitle("Hearing Trends")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var insufficientDataView: some View {
        VStack(spacing: 24) {
            Image(systemName: "chart.line.uptrend.xyaxis.circle")
                .font(.system(size: 80))
                .foregroundStyle(accentGradient)
            
            VStack(spacing: 12) {
                Text("Not Enough Data")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("Complete at least 2 Sonaura hearing tests to see trends and track changes over time.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if dataManager.testSessions.count == 1 {
                VStack(spacing: 12) {
                    Text("You have 1 test completed")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Take another test to start tracking your hearing trends")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 40)
            }
        }
    }
    
    private var trendContentView: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Summary stats
                summaryStatsView
                
                // Chart with controls
                VStack(spacing: 20) {
                    if #available(iOS 16.0, *) {
                        chartView
                    } else {
                        fallbackChartView
                    }
                    
                    // Segmented controls underneath the graph
                    VStack(spacing: 20) {
                        // Ear selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ear")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Picker("Ear", selection: $selectedEar) {
                                Text("Right Ear").tag(TestEar.right)
                                Text("Left Ear").tag(TestEar.left)
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        Divider()
                        
                        // Metric selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Metric")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            Picker("Metric", selection: $selectedMetric) {
                                ForEach(TrendMetric.allCases, id: \.self) { metric in
                                    Label(metric.rawValue, systemImage: metric.icon)
                                        .tag(metric)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .padding(20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
                
                // Insights
                insightsView
                
                // Recommendations
                recommendationsView
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
        }
    }
    
    private var summaryStatsView: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text("Trend Summary")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            let trendData = dataManager.getTrendData(for: selectedEar)
            let firstTest = trendData.first
            let latestTest = trendData.last
            let change = (latestTest?.pta ?? 0) - (firstTest?.pta ?? 0)
            
            HStack(spacing: 20) {
                StatCard(
                    title: "First Test",
                    value: firstTest != nil ? "\(Int(firstTest!.pta)) dB" : "N/A",
                    subtitle: firstTest?.dateTimeString ?? "",
                    color: .blue
                )
                
                StatCard(
                    title: "Latest Test",
                    value: latestTest != nil ? "\(Int(latestTest!.pta)) dB" : "N/A",
                    subtitle: latestTest?.dateTimeString ?? "",
                    color: .green
                )
                
                StatCard(
                    title: "Change",
                    value: change >= 0 ? "+\(Int(change)) dB" : "\(Int(change)) dB",
                    subtitle: change >= 0 ? "Worse" : "Better",
                    color: change >= 0 ? .red : .green
                )
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    @available(iOS 16.0, *)
    private var chartView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: selectedMetric.icon)
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text(selectedMetric == .pta ? "Pure Tone Average (PTA) Trends" : "Hearing Classification Trends")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            let trendData = dataManager.getTrendData(for: selectedEar)
            
            Group {
                if selectedMetric == .pta {
                    Chart(trendData) { dataPoint in
                        LineMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("PTA", dataPoint.pta)
                        )
                        .foregroundStyle(accentGradient)
                        .lineStyle(StrokeStyle(lineWidth: 3))
                        
                        PointMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("PTA", dataPoint.pta)
                        )
                        .foregroundStyle(accentGradient)
                        .symbolSize(100)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let db = value.as(Double.self) {
                                    Text("\(Int(db))")
                                        .font(.caption)
                                }
                            }
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYAxisLabel("dB HL (Hearing Level)", position: .leading, alignment: .center)
                } else {
                    Chart(trendData) { dataPoint in
                        BarMark(
                            x: .value("Date", dataPoint.date),
                            y: .value("Classification", classificationValue(dataPoint.classification))
                        )
                        .foregroundStyle(classificationColor(dataPoint.classification))
                        .cornerRadius(4)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let val = value.as(Double.self) {
                                    Text(classificationLabel(from: val))
                                        .font(.caption)
                                }
                            }
                            AxisGridLine()
                            AxisTick()
                        }
                    }
                    .chartYScale(domain: 0...7)
                    .chartYAxisLabel("Classification", position: .leading, alignment: .center)
                }
            }
            .frame(height: 300)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            // Show date and time for better precision
                            Text(date, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                        }
                    }
                    AxisGridLine()
                    AxisTick()
                }
            }
            .chartXAxisLabel("Date & Time", position: .bottom, alignment: .center)
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var fallbackChartView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: selectedMetric.icon)
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text(selectedMetric == .pta ? "Pure Tone Average (PTA) Trends" : "Hearing Classification Trends")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            Text("Chart visualization requires iOS 16 or later")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(height: 250)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var insightsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)
                Text("Insights")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            let trendData = dataManager.getTrendData(for: selectedEar)
            let insights = generateInsights(from: trendData)
            
            ForEach(insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var recommendationsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .foregroundStyle(.red)
                    .font(.title2)
                Text("Recommendations")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            let trendData = dataManager.getTrendData(for: selectedEar)
            let recommendations = generateRecommendations(from: trendData)
            
            ForEach(recommendations, id: \.self) { recommendation in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private func generateInsights(from trendData: [TrendDataPoint]) -> [String] {
        var insights: [String] = []
        
        if trendData.count < 2 {
            return ["Complete more tests to generate insights"]
        }
        
        let firstPTA = trendData.first?.pta ?? 0
        let latestPTA = trendData.last?.pta ?? 0
        let change = latestPTA - firstPTA
        
        if abs(change) > 5 {
            insights.append("Your hearing has \(change > 0 ? "declined" : "improved") by \(Int(abs(change))) dB since your first test")
        } else {
            insights.append("Your hearing has remained relatively stable")
        }
        
        // Check for recent trends
        if trendData.count >= 3 {
            let recentChange = trendData.last!.pta - trendData[trendData.count - 2].pta
            if abs(recentChange) > 3 {
                insights.append("Your most recent test shows a \(recentChange > 0 ? "decline" : "improvement") of \(Int(abs(recentChange))) dB")
            }
        }
        
        // Check classification changes
        let firstClassification = trendData.first?.classification ?? .normal
        let latestClassification = trendData.last?.classification ?? .normal
        if firstClassification != latestClassification {
            insights.append("Your hearing classification has changed from \(firstClassification.rawValue) to \(latestClassification.rawValue)")
        }
        
        return insights
    }
    
    private func generateRecommendations(from trendData: [TrendDataPoint]) -> [String] {
        var recommendations: [String] = []
        
        if trendData.isEmpty {
            return ["Complete regular hearing tests to track changes over time"]
        }
        
        let latestPTA = trendData.last?.pta ?? 0
        let latestClassification = trendData.last?.classification ?? .normal
        
        // Based on current hearing level
        if latestClassification == .severe || latestClassification == .profound {
            recommendations.append("Consider consulting an audiologist for comprehensive evaluation")
            recommendations.append("Explore hearing aid options if not already using them")
        } else if latestClassification == .moderate || latestClassification == .moderatelySevere {
            recommendations.append("Schedule a professional hearing evaluation")
            recommendations.append("Consider hearing aids for improved communication")
        } else if latestPTA > 25 {
            recommendations.append("Monitor your hearing regularly with professional tests")
            recommendations.append("Protect your hearing from loud noises")
        } else {
            recommendations.append("Continue regular hearing monitoring")
            recommendations.append("Maintain healthy hearing habits")
        }
        
        // Based on trends
        if trendData.count >= 2 {
            let change = trendData.last!.pta - trendData.first!.pta
            if change > 10 {
                recommendations.append("Recent changes warrant professional evaluation")
            }
        }
        
        // General recommendations
        recommendations.append("Follow safe listening practices (keep volume below 85 dB)")
        recommendations.append("Take breaks during extended listening sessions")
        
        return recommendations
    }
    
    // MARK: - Helper Functions
    
    private func classificationValue(_ classification: HearingClassification) -> Double {
        switch classification {
        case .exceptional: return 0.0
        case .normal: return 1.0
        case .normalVariation: return 2.0
        case .mild: return 3.0
        case .moderate: return 4.0
        case .moderatelySevere: return 5.0
        case .severe: return 6.0
        case .profound: return 7.0
        }
    }
    
    private func classificationLabel(from value: Double) -> String {
        let intValue = Int(value.rounded())
        switch intValue {
        case 0: return "Exceptional"
        case 1: return "Normal"
        case 2: return "Normal Variation"
        case 3: return "Mild"
        case 4: return "Moderate"
        case 5: return "Moderately Severe"
        case 6: return "Severe"
        case 7: return "Profound"
        default: return ""
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
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    TrendTrackingView()
}

