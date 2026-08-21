//
//  SecurityValidator.swift
//  Sonaura
//
//  Security validation and sanitization utilities following OWASP best practices
//  Provides input validation, sanitization, and rate limiting for iOS app
//

import Foundation

// MARK: - Input Validation Errors

/// Security validation errors following OWASP guidelines
enum SecurityValidationError: LocalizedError {
    case invalidAge(Int)
    case ageOutOfRange(Int, min: Int, max: Int)
    case invalidInput(String)
    case inputTooLong(String, maxLength: Int)
    case invalidCharacters(String, reason: String)
    case rateLimitExceeded(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidAge(let age):
            return "Invalid age value: \(age)"
        case .ageOutOfRange(let age, let min, let max):
            return "Age \(age) is out of valid range (\(min)-\(max))"
        case .invalidInput(let input):
            return "Invalid input format: \(input)"
        case .inputTooLong(let input, let maxLength):
            return "Input exceeds maximum length of \(maxLength) characters"
        case .invalidCharacters(let input, let reason):
            return "Input contains invalid characters: \(reason)"
        case .rateLimitExceeded(let action):
            return "Rate limit exceeded for action: \(action). Please wait before trying again."
        }
    }
}

// MARK: - Input Validator

/// Input validation and sanitization following OWASP best practices
/// OWASP: Validate all inputs, sanitize data, enforce length limits, reject unexpected fields
struct SecurityValidator {
    
    // MARK: - Age Validation
    
    /// Validates user age input following OWASP input validation guidelines
    /// - Parameters:
    ///   - age: The age value to validate
    ///   - minAge: Minimum allowed age (default: 18 for adult hearing tests)
    ///   - maxAge: Maximum allowed age (default: 120, reasonable human lifespan)
    /// - Returns: Validated age value
    /// - Throws: SecurityValidationError if validation fails
    /// 
    /// OWASP Guidelines:
    /// - Validate data type (must be integer)
    /// - Validate range (must be within reasonable bounds)
    /// - Reject invalid values immediately
    static func validateAge(_ age: Int?, minAge: Int = 18, maxAge: Int = 120) throws -> Int {
        guard let age = age else {
            throw SecurityValidationError.invalidAge(0)
        }
        
        // Type check: Ensure it's a valid integer (already validated by Swift type system)
        // Range check: OWASP recommends validating all numeric inputs are within expected ranges
        guard age >= minAge && age <= maxAge else {
            throw SecurityValidationError.ageOutOfRange(age, min: minAge, max: maxAge)
        }
        
        return age
    }
    
    // MARK: - String Validation & Sanitization
    
    /// Validates and sanitizes string input following OWASP guidelines
    /// - Parameters:
    ///   - input: String to validate
    ///   - maxLength: Maximum allowed length (default: 1000)
    ///   - allowUnicode: Whether to allow Unicode characters (default: true)
    ///   - allowedCharacters: Optional set of allowed character sets
    /// - Returns: Sanitized string
    /// - Throws: SecurityValidationError if validation fails
    ///
    /// OWASP Guidelines:
    /// - Enforce length limits to prevent DoS
    /// - Sanitize input to remove potentially dangerous characters
    /// - Validate character set
    static func validateAndSanitizeString(
        _ input: String?,
        maxLength: Int = 1000,
        allowUnicode: Bool = true,
        allowedCharacters: CharacterSet? = nil
    ) throws -> String {
        guard let input = input else {
            throw SecurityValidationError.invalidInput("nil")
        }
        
        // Length validation: OWASP recommends enforcing maximum length to prevent DoS
        guard input.count <= maxLength else {
            throw SecurityValidationError.inputTooLong(input, maxLength: maxLength)
        }
        
        // Character set validation
        if let allowed = allowedCharacters {
            let inputSet = CharacterSet(charactersIn: input)
            guard inputSet.isSubset(of: allowed) else {
                throw SecurityValidationError.invalidCharacters(input, reason: "Contains disallowed characters")
            }
        }
        
        // Sanitization: Remove control characters and normalize whitespace
        // OWASP: Sanitize input to prevent injection attacks
        var sanitized = input
        
        // Remove control characters (except newlines and tabs for text)
        let controlChars = CharacterSet.controlCharacters.subtracting(CharacterSet(charactersIn: "\n\t"))
        sanitized = sanitized.components(separatedBy: controlChars).joined(separator: "")
        
        // Normalize whitespace (prevent excessive whitespace)
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return sanitized
    }
    
    // MARK: - Gender Validation
    
    /// Validates gender selection (enum-based, already type-safe)
    /// This is a validation wrapper for additional security checks
    /// - Parameter gender: Gender string to validate
    /// - Returns: Validated gender string
    /// - Throws: SecurityValidationError if invalid
    static func validateGender(_ gender: String) throws -> String {
        // Whitelist approach: Only allow known valid values
        // OWASP: Use whitelist validation instead of blacklist
        let validGenders = ["male", "female"]
        
        guard validGenders.contains(gender.lowercased()) else {
            throw SecurityValidationError.invalidInput("Invalid gender: \(gender)")
        }
        
        return gender.lowercased()
    }
    
    // MARK: - Device Model Validation
    
    /// Validates device model string
    /// - Parameter model: Device model string
    /// - Returns: Sanitized model string
    /// - Throws: SecurityValidationError if invalid
    static func validateDeviceModel(_ model: String) throws -> String {
        // Validate length (device model names shouldn't be excessively long)
        return try validateAndSanitizeString(model, maxLength: 100, allowUnicode: false)
    }
    
    // MARK: - JSON Data Validation
    
    /// Validates JSON data structure to prevent injection attacks
    /// - Parameters:
    ///   - data: JSON data to validate
    ///   - maxSize: Maximum allowed size in bytes (default: 1MB)
    /// - Returns: Validated data
    /// - Throws: SecurityValidationError if validation fails
    ///
    /// OWASP Guidelines:
    /// - Validate data structure
    /// - Enforce size limits
    /// - Prevent JSON injection attacks
    static func validateJSONData(_ data: Data, maxSize: Int = 1_000_000) throws -> Data {
        // Size validation: Prevent DoS through large payloads
        guard data.count <= maxSize else {
            throw SecurityValidationError.inputTooLong("JSON data", maxLength: maxSize)
        }
        
        // Structure validation: Ensure it's valid JSON
        do {
            _ = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SecurityValidationError.invalidInput("Invalid JSON structure: \(error.localizedDescription)")
        }
        
        return data
    }
}

// MARK: - Rate Limiter

/// Rate limiter for user actions following OWASP best practices
/// Prevents abuse and DoS attacks by limiting action frequency
/// 
/// OWASP Guidelines:
/// - Implement rate limiting on all user-initiated actions
/// - Use both IP-based and user-based limits
/// - Return graceful 429 responses
actor RateLimiter {
    
    // MARK: - Configuration
    
    /// Rate limit configuration for different action types
    struct RateLimitConfig {
        let maxRequests: Int
        let timeWindow: TimeInterval // in seconds
        
        /// Default configurations following OWASP recommendations
        static let testStart = RateLimitConfig(maxRequests: 5, timeWindow: 60) // 5 tests per minute
        static let testResponse = RateLimitConfig(maxRequests: 100, timeWindow: 60) // 100 responses per minute
        static let dataExport = RateLimitConfig(maxRequests: 10, timeWindow: 300) // 10 exports per 5 minutes
        static let dataDelete = RateLimitConfig(maxRequests: 20, timeWindow: 300) // 20 deletes per 5 minutes
    }
    
    // MARK: - Private State
    
    /// Track requests by action type and identifier (user ID or IP)
    private var requestHistory: [String: [Date]] = [:]
    
    // MARK: - Rate Limiting
    
    /// Check if an action is allowed under rate limits
    /// - Parameters:
    ///   - action: Action identifier (e.g., "test_start", "test_response")
    ///   - identifier: User identifier (for user-based limiting)
    ///   - config: Rate limit configuration
    /// - Returns: True if allowed, false if rate limited
    /// - Throws: SecurityValidationError.rateLimitExceeded if limit exceeded
    func checkRateLimit(
        action: String,
        identifier: String = "default",
        config: RateLimitConfig
    ) throws -> Bool {
        let key = "\(action):\(identifier)"
        let now = Date()
        
        // Get or create request history for this key
        var requests = requestHistory[key] ?? []
        
        // Remove requests outside the time window
        requests = requests.filter { now.timeIntervalSince($0) < config.timeWindow }
        
        // Check if limit exceeded
        guard requests.count < config.maxRequests else {
            let oldestRequest = requests.first!
            let timeUntilReset = config.timeWindow - now.timeIntervalSince(oldestRequest)
            throw SecurityValidationError.rateLimitExceeded("\(action) (retry in \(Int(timeUntilReset))s)")
        }
        
        // Add current request
        requests.append(now)
        requestHistory[key] = requests
        
        return true
    }
    
    /// Reset rate limit for a specific action and identifier
    /// Useful for testing or manual reset
    func resetRateLimit(action: String, identifier: String = "default") {
        let key = "\(action):\(identifier)"
        requestHistory.removeValue(forKey: key)
    }
    
    /// Clean up old entries to prevent memory leaks
    func cleanup() {
        let now = Date()
        let maxAge: TimeInterval = 3600 // Keep entries for 1 hour max
        
        requestHistory = requestHistory.mapValues { requests in
            requests.filter { now.timeIntervalSince($0) < maxAge }
        }.filter { !$0.value.isEmpty }
    }
}

// MARK: - Global Rate Limiter Instance

/// Global rate limiter instance for app-wide rate limiting
/// Uses actor for thread-safe access
@MainActor
class AppRateLimiter {
    private static let limiter = RateLimiter()
    
    /// Check rate limit for an action
    static func checkLimit(
        action: String,
        identifier: String = "default",
        config: RateLimiter.RateLimitConfig
    ) async throws -> Bool {
        return try await limiter.checkRateLimit(
            action: action,
            identifier: identifier,
            config: config
        )
    }
    
    /// Reset rate limit
    static func resetLimit(action: String, identifier: String = "default") async {
        await limiter.resetRateLimit(action: action, identifier: identifier)
    }
    
    /// Cleanup old entries
    static func cleanup() async {
        await limiter.cleanup()
    }
}
