import SwiftUI

/// Safety information and warnings based on NIOSH/WHO guidelines
struct SafetyWarningsView: View {
    let testSession: HearingTestSession?
    @State private var showDetailedInfo = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General safety header
            HStack(spacing: 12) {
                Image(systemName: "shield.fill")
                    .foregroundStyle(.blue)
                    .font(.title2)
                Text("Safe Listening Information")
                    .font(.headline)
            }
            
            // NIOSH/WHO guidelines summary
            VStack(alignment: .leading, spacing: 12) {
                SafetyGuideline(
                    icon: "clock.fill",
                    title: "85 dB for 8 hours",
                    description: "NIOSH recommends maximum daily exposure"
                )
                
                SafetyGuideline(
                    icon: "speaker.wave.3.fill",
                    title: "60% max volume rule",
                    description: "WHO recommends keeping devices below 60% volume"
                )
                
                SafetyGuideline(
                    icon: "ear.fill",
                    title: "Take listening breaks",
                    description: "Rest your ears every hour of continuous listening"
                )
            }
            
            // Exposure time calculator
            if showDetailedInfo {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Safe Listening Times (NIOSH)")
                        .font(.subheadline.weight(.semibold))
                    
                    ForEach(safeListeningLevels, id: \.level) { item in
                        HStack {
                            Text("\(item.level) dB")
                                .font(.caption.monospacedDigit())
                                .frame(width: 60, alignment: .leading)
                            Rectangle()
                                .fill(item.color.opacity(0.3))
                                .frame(width: 4, height: 20)
                            Text(item.duration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Test-specific warnings (if session exists)
            if let session = testSession {
                Divider()
                testSpecificWarnings(session: session)
            }
            
            // Toggle detailed info
            Button(action: { showDetailedInfo.toggle() }) {
                HStack {
                    Text(showDetailedInfo ? "Show less" : "Show more safety info")
                        .font(.caption)
                    Image(systemName: showDetailedInfo ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    @ViewBuilder
    private func testSpecificWarnings(session: HearingTestSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Test Results")
                .font(.subheadline.weight(.semibold))
            
            // Check if any thresholds indicate significant hearing loss
            let maxThreshold = session.results.map { $0.thresholdDB }.max() ?? 0
            
            if maxThreshold > 40 {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elevated hearing thresholds detected")
                            .font(.caption.weight(.semibold))
                        Text("You may need higher volumes to hear clearly. Be cautious with prolonged listening at high volumes and consider consulting an audiologist.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Volume usage during test
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
                Text("This test used maximum device volume with controlled tone levels. For daily listening, follow the 60/60 rule: 60% volume for no more than 60 minutes at a time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var safeListeningLevels: [(level: Int, duration: String, color: Color)] {
        [
            (85, "8 hours/day", .green),
            (88, "4 hours/day", .green),
            (91, "2 hours/day", .yellow),
            (94, "1 hour/day", .yellow),
            (97, "30 minutes/day", .orange),
            (100, "15 minutes/day", .orange),
            (103, "7.5 minutes/day", .red),
            (106, "3.75 minutes/day", .red)
        ]
    }
}

/// Individual safety guideline row
struct SafetyGuideline: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Exposure tracking helper (for future implementation)
struct ExposureTracker {
    /// Calculate safe listening time remaining based on NIOSH 3-dB exchange rate
    /// - Parameters:
    ///   - levelDB: Current listening level in dB
    ///   - dailyExposureMinutes: Minutes already exposed today at this level
    /// - Returns: Remaining safe listening time in minutes
    static func remainingSafeTime(levelDB: Double, dailyExposureMinutes: Double = 0) -> Double {
        // NIOSH: 85 dB = 480 minutes (8 hours)
        // 3 dB exchange rate: double/halve time for every 3 dB change
        
        let referenceLevelDB = 85.0
        let referenceTimeMinutes = 480.0
        
        // Calculate max safe time for this level
        let levelDifference = levelDB - referenceLevelDB
        let exchangeRate = 3.0
        let maxSafeTime = referenceTimeMinutes * pow(2.0, -levelDifference / exchangeRate)
        
        // Subtract already used time
        return max(0, maxSafeTime - dailyExposureMinutes)
    }
    
    /// Get safe listening recommendation for a given level
    static func recommendation(for levelDB: Double) -> String {
        if levelDB <= 70 {
            return "Safe for extended listening"
        } else if levelDB <= 85 {
            return "Safe for up to 8 hours daily"
        } else if levelDB <= 95 {
            return "Limit to 1-4 hours daily"
        } else if levelDB <= 105 {
            return "Limit to 15 minutes or less daily"
        } else {
            return "Unsafe for any duration - risk of immediate hearing damage"
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            SafetyWarningsView(testSession: nil)
            
            let sampleSession = HearingTestSession(
                results: [
                    ThresholdResult(frequencyHz: 1000, ear: .right, thresholdDB: 45, presentations: [], reliability: .standard)
                ],
                startTime: Date(),
                endTime: Date(),
                deviceModel: "AirPods Pro",
                userAge: 30,
                userGender: .male
            )
            SafetyWarningsView(testSession: sampleSession)
        }
        .padding()
    }
}

