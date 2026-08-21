import Foundation
import SwiftData
import Combine

/// SwiftData model for persistent storage of hearing test results
@Model
final class StoredHearingTestSession {
    @Attribute(.unique) var id: UUID
    var startTime: Date
    var endTime: Date
    var deviceModel: String
    var userAge: Int?
    var userGender: String // Store as string for SwiftData compatibility
    
    // Store results as JSON data
    @Attribute(.externalStorage) var resultsData: Data
    
    // Computed properties for easy access
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: startTime)
    }
    
    init(from session: HearingTestSession) {
        self.id = session.id
        self.startTime = session.startTime
        self.endTime = session.endTime
        
        // OWASP: Validate and sanitize device model input
        do {
            self.deviceModel = try SecurityValidator.validateDeviceModel(session.deviceModel)
        } catch {
            // Fallback to sanitized version if validation fails
            self.deviceModel = (try? SecurityValidator.validateAndSanitizeString(session.deviceModel, maxLength: 100)) ?? "Unknown"
        }
        
        // OWASP: Validate age input
        if let age = session.userAge {
            do {
                self.userAge = try SecurityValidator.validateAge(age)
            } catch {
                // Invalid age - don't store it
                self.userAge = nil
            }
        } else {
            self.userAge = nil
        }
        
        // OWASP: Validate gender input
        do {
            self.userGender = try SecurityValidator.validateGender(session.userGender?.rawValue ?? "male")
        } catch {
            // Fallback to default
            self.userGender = "male"
        }
        
        // OWASP: Validate JSON data size and structure
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let jsonData = try? encoder.encode(session.results) {
            // Validate JSON data before storing
            do {
                self.resultsData = try SecurityValidator.validateJSONData(jsonData, maxSize: 1_000_000)
            } catch {
                // If validation fails, use empty data (better than corrupted data)
                print("⚠️ Security: JSON data validation failed: \(error.localizedDescription)")
                self.resultsData = Data()
            }
        } else {
            self.resultsData = Data()
        }
    }
    
    /// Convert back to HearingTestSession for display
    func toHearingTestSession() -> HearingTestSession? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        guard let results = try? decoder.decode([ThresholdResult].self, from: resultsData) else {
            return nil
        }
        
        let gender: ISO7029Calculator.Gender = userGender == "female" ? .female : .male
        
        return HearingTestSession(
            results: results,
            startTime: startTime,
            endTime: endTime,
            deviceModel: deviceModel,
            userAge: userAge,
            userGender: gender
        )
    }
    
    /// Get Pure Tone Average for an ear
    func pureToneAverage(ear: TestEar) -> Double? {
        guard let session = toHearingTestSession() else { return nil }
        return session.pureToneAverage(ear: ear)
    }
    
    /// Get overall classification for an ear
    func overallClassification(ear: TestEar) -> HearingClassification {
        guard let session = toHearingTestSession() else { return .normal }
        return session.overallClassification(ear: ear)
    }
}

/// Data manager for handling local storage operations
@MainActor
class HearingTestDataManager: ObservableObject {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    @Published var testSessions: [StoredHearingTestSession] = []
    @Published var isLoading = false
    
    init() {
        // Create SwiftData model container
        do {
            let schema = Schema([StoredHearingTestSession.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContext = modelContainer.mainContext
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
        
        loadTestSessions()
    }
    
    /// Load all test sessions from storage
    func loadTestSessions() {
        isLoading = true
        defer { isLoading = false }
        
        let descriptor = FetchDescriptor<StoredHearingTestSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        do {
            testSessions = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to load test sessions: \(error)")
            testSessions = []
        }
    }
    
    /// Save a new test session with rate limiting
    /// OWASP: Rate limit data operations to prevent abuse
    func saveTestSession(_ session: HearingTestSession) {
        // OWASP: Rate limiting for data save operations
        Task { @MainActor in
            do {
                // Stable per-install identity. A fresh UUID per call made the
                // rate-limit key unique every time, so the limit never tripped
                // and RateLimiter.requestHistory grew without bound.
                let userIdentifier = HearingTestViewModel.rateLimitIdentity
                _ = try await AppRateLimiter.checkLimit(
                    action: "data_save",
                    identifier: userIdentifier,
                    config: RateLimiter.RateLimitConfig(maxRequests: 50, timeWindow: 60)
                )
                
                // Proceed with save
                let storedSession = StoredHearingTestSession(from: session)
                modelContext.insert(storedSession)
                
                do {
                    try modelContext.save()
                    loadTestSessions() // Refresh the list
                } catch {
                    print("Failed to save test session: \(error)")
                }
                
            } catch let error as SecurityValidationError {
                print("⚠️ Rate limit exceeded for save: \(error.localizedDescription)")
                // Don't save if rate limited
            } catch {
                print("❌ Unexpected error: \(error)")
            }
        }
    }
    
    /// Delete a test session with rate limiting
    /// OWASP: Rate limit delete operations to prevent abuse
    func deleteTestSession(_ session: StoredHearingTestSession) {
        Task { @MainActor in
            do {
                // OWASP: Rate limiting for delete operations
                // Stable per-install identity. A fresh UUID per call made the
                // rate-limit key unique every time, so the limit never tripped
                // and RateLimiter.requestHistory grew without bound.
                let userIdentifier = HearingTestViewModel.rateLimitIdentity
                _ = try await AppRateLimiter.checkLimit(
                    action: "data_delete",
                    identifier: userIdentifier,
                    config: .dataDelete
                )
                
                // Proceed with delete
                modelContext.delete(session)
                
                do {
                    try modelContext.save()
                    loadTestSessions() // Refresh the list
                } catch {
                    print("Failed to delete test session: \(error)")
                }
                
            } catch let error as SecurityValidationError {
                print("⚠️ Rate limit exceeded for delete: \(error.localizedDescription)")
                // Don't delete if rate limited
            } catch {
                print("❌ Unexpected error: \(error)")
            }
        }
    }
    
    /// Delete all test sessions
    func deleteAllTestSessions() {
        for session in testSessions {
            modelContext.delete(session)
        }
        
        do {
            try modelContext.save()
            loadTestSessions() // Refresh the list
        } catch {
            print("Failed to delete all test sessions: \(error)")
        }
    }
    
    /// Get storage information
    func getStorageInfo() -> (count: Int, totalSize: String) {
        let count = testSessions.count
        let totalSizeBytes = testSessions.reduce(0) { $0 + $1.resultsData.count }
        let totalSize = ByteCountFormatter.string(fromByteCount: Int64(totalSizeBytes), countStyle: .file)
        
        return (count, totalSize)
    }
    
    /// Get trend data for comparing tests over time
    /// Returns data sorted chronologically by startTime
    func getTrendData(for ear: TestEar) -> [TrendDataPoint] {
        return testSessions
            .compactMap { storedSession in
                guard let pta = storedSession.pureToneAverage(ear: ear) else { return nil }
                return TrendDataPoint(
                    date: storedSession.startTime,
                    pta: pta,
                    classification: storedSession.overallClassification(ear: ear)
                )
            }
            .sorted { $0.date < $1.date } // Ensure chronological order
    }
}

/// Data point for trend analysis
struct TrendDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let pta: Double
    let classification: HearingClassification
    
    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
    
    var dateTimeString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
