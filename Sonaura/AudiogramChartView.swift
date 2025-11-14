import SwiftUI
import Charts

/// Interactive audiogram chart showing hearing thresholds across frequencies
/// Y-axis: dB HL (0 at top = normal, larger values = worse hearing)
/// X-axis: Frequency (Hz) on logarithmic scale
struct AudiogramChartView: View {
    let results: [ThresholdResult]
    let ear: TestEar
    let userAge: Int?
    let userGender: ISO7029Calculator.Gender
    let showNormalRange: Bool
    
    init(
        results: [ThresholdResult],
        ear: TestEar,
        userAge: Int? = nil,
        userGender: ISO7029Calculator.Gender = .male,
        showNormalRange: Bool = true
    ) {
        self.results = results.filter { $0.ear == ear }.sorted { $0.frequencyHz < $1.frequencyHz }
        self.ear = ear
        self.userAge = userAge
        self.userGender = userGender
        self.showNormalRange = showNormalRange
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(ear.displayName) Audiogram")
                .font(.headline)
            
            if #available(iOS 16.0, *) {
                modernChart
                    .frame(height: 300)
            } else {
                fallbackChart
                    .frame(height: 300)
            }
            
            legend
        }
    }
    
    @available(iOS 16.0, *)
    private var modernChart: some View {
        Chart {
            // Normal hearing range (shaded area)
            if showNormalRange {
                ForEach(frequencies, id: \.self) { freq in
                    let normalThreshold = getNormalThreshold(frequency: freq)
                    RectangleMark(
                        x: .value("Frequency", freq),
                        yStart: .value("Min", -10.0),
                        yEnd: .value("Max", normalThreshold + 25.0)
                    )
                    .foregroundStyle(Color.green.opacity(0.15))
                }
            }
            
            // User's thresholds (line + points)
            ForEach(results) { result in
                LineMark(
                    x: .value("Frequency", result.frequencyHz),
                    y: .value("Threshold", result.thresholdDB)
                )
                .foregroundStyle(earColor)
                .lineStyle(StrokeStyle(lineWidth: 3))
                .interpolationMethod(.catmullRom)
            }
            
            ForEach(results) { result in
                PointMark(
                    x: .value("Frequency", result.frequencyHz),
                    y: .value("Threshold", result.thresholdDB)
                )
                .foregroundStyle(earColor)
                .symbol(Circle())
                .symbolSize(120)
                
                // Classification indicator
                PointMark(
                    x: .value("Frequency", result.frequencyHz),
                    y: .value("Threshold", result.thresholdDB)
                )
                .foregroundStyle(classificationColor(result.thresholdDB))
                .symbol(Circle())
                .symbolSize(60)
            }
            
            // Age-matched normal median (if age provided)
            if let age = userAge {
                ForEach(frequencies, id: \.self) { freq in
                    LineMark(
                        x: .value("Frequency", freq),
                        y: .value("Expected", expectedMedian(freq: freq, age: age))
                    )
                    .foregroundStyle(Color.gray.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: frequencies) { value in
                AxisValueLabel {
                    if let freq = value.as(Int.self) {
                        Text(formatFrequency(freq))
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks(values: [-10, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110]) { value in
                AxisValueLabel {
                    if let db = value.as(Double.self) {
                        Text("\(Int(db))")
                            .font(.caption)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYScale(domain: -10...110)
    }
    
    private var fallbackChart: some View {
        // Simple fallback for iOS < 16
        GeometryReader { geometry in
            ZStack {
                // Grid background
                ForEach(0..<12) { i in
                    let y = CGFloat(i) * geometry.size.height / 11
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                }
                
                // Plot points and lines
                if !results.isEmpty {
                    Path { path in
                        for (index, result) in results.enumerated() {
                            let x = xPosition(for: result.frequencyHz, in: geometry.size.width)
                            let y = yPosition(for: result.thresholdDB, in: geometry.size.height)
                            
                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(earColor, lineWidth: 2)
                    
                    ForEach(results) { result in
                        Circle()
                            .fill(classificationColor(result.thresholdDB))
                            .frame(width: 10, height: 10)
                            .position(
                                x: xPosition(for: result.frequencyHz, in: geometry.size.width),
                                y: yPosition(for: result.thresholdDB, in: geometry.size.height)
                            )
                    }
                }
            }
        }
    }
    
    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Circle()
                    .fill(earColor)
                    .frame(width: 10, height: 10)
                Text(ear.displayName)
                    .font(.caption)
            }
            
            if userAge != nil {
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.5))
                        .frame(width: 20, height: 2)
                    Text("Expected (age \(userAge ?? 0))")
                        .font(.caption)
                }
            }
            
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.green.opacity(0.3))
                    .frame(width: 10, height: 10)
                Text("Normal range")
                    .font(.caption)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var frequencies: [Int] {
        [250, 500, 1000, 2000, 4000, 8000, 12000]
    }
    
    private var earColor: Color {
        ear == .right ? .blue : .red
    }
    
    private func classificationColor(_ thresholdDB: Double) -> Color {
        let classification = ISO7029Calculator.classify(thresholdDB: thresholdDB)
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
    
    private func getNormalThreshold(frequency: Int) -> Double {
        let age = userAge ?? 25
        return ISO7029Calculator.medianThreshold(age: age, frequency: frequency, gender: userGender)
    }
    
    private func expectedMedian(freq: Int, age: Int) -> Double {
        return ISO7029Calculator.medianThreshold(age: age, frequency: freq, gender: userGender)
    }
    
    private func formatFrequency(_ freq: Int) -> String {
        if freq >= 1000 {
            return "\(freq / 1000)k"
        }
        return "\(freq)"
    }
    
    // Fallback chart positioning helpers
    private func xPosition(for frequency: Int, in width: CGFloat) -> CGFloat {
        let freqIndex = frequencies.firstIndex(of: frequency) ?? 0
        return CGFloat(freqIndex) * width / CGFloat(frequencies.count - 1)
    }
    
    private func yPosition(for thresholdDB: Double, in height: CGFloat) -> CGFloat {
        // Map -10 to 110 dB HL to height
        let normalizedValue = (thresholdDB + 10) / 120.0
        return CGFloat(normalizedValue) * height
    }
}

#Preview {
    let sampleResults = [
        ThresholdResult(frequencyHz: 250, ear: .right, thresholdDB: 10, presentations: [], reliability: .standard),
        ThresholdResult(frequencyHz: 500, ear: .right, thresholdDB: 8, presentations: [], reliability: .standard),
        ThresholdResult(frequencyHz: 1000, ear: .right, thresholdDB: 5, presentations: [], reliability: .standard),
        ThresholdResult(frequencyHz: 2000, ear: .right, thresholdDB: 12, presentations: [], reliability: .standard),
        ThresholdResult(frequencyHz: 4000, ear: .right, thresholdDB: 18, presentations: [], reliability: .standard),
        ThresholdResult(frequencyHz: 8000, ear: .right, thresholdDB: 25, presentations: [], reliability: .standard),
    ]
    
    return AudiogramChartView(
        results: sampleResults,
        ear: .right,
        userAge: 30,
        userGender: .male,
        showNormalRange: true
    )
    .padding()
}

