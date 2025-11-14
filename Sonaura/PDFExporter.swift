import Foundation
import PDFKit
import UIKit

/// Generates PDF reports for hearing test results
class PDFExporter {
    
    /// Generate a PDF report for a hearing test session
    static func generatePDF(for session: HearingTestSession) -> Data {
        let pdfMetaData = [
            kCGPDFContextCreator: "Sonaura",
            kCGPDFContextAuthor: "Sonaura Hearing Test App",
            kCGPDFContextTitle: "Sonaura Test Report"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let pageWidth = 8.5 * 72.0 // US Letter width in points
        let pageHeight = 11.0 * 72.0 // US Letter height in points
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        
        return renderer.pdfData { context in
            context.beginPage()
            
            // Draw header
            drawHeader(in: pageRect)
            
            // Draw test summary
            let summaryY = drawTestSummary(session: session, in: pageRect)
            
            // Draw audiogram charts
            let chartY = drawAudiograms(session: session, startY: summaryY, in: pageRect)
            
            // Draw detailed results
            let detailsY = drawDetailedResults(session: session, startY: chartY, in: pageRect)
            
            // Draw safety information
            drawSafetyInformation(startY: detailsY, in: pageRect)
            
            // Draw footer
            drawFooter(in: pageRect)
        }
    }
    
    private static func drawHeader(in rect: CGRect) {
        let headerRect = CGRect(x: 40, y: 40, width: rect.width - 80, height: 80)
        
        // App title
        let titleFont = UIFont.boldSystemFont(ofSize: 24)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        "Sonaura Hearing Test Report".draw(in: headerRect, withAttributes: titleAttributes)
        
        // Subtitle
        let subtitleRect = CGRect(x: 40, y: 70, width: rect.width - 80, height: 30)
        let subtitleFont = UIFont.systemFont(ofSize: 14)
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.gray
        ]
        "Clinically-validated hearing threshold assessment".draw(in: subtitleRect, withAttributes: subtitleAttributes)
    }
    
    private static func drawTestSummary(session: HearingTestSession, in rect: CGRect) -> CGFloat {
        let startY: CGFloat = 140
        var currentY = startY
        
        // Test information
        _ = CGRect(x: 40, y: currentY, width: rect.width - 80, height: 120)
        currentY += 130
        
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        "Test Information".draw(in: CGRect(x: 40, y: startY, width: 200, height: 25), withAttributes: titleAttributes)
        
        // Test details
        let detailFont = UIFont.systemFont(ofSize: 12)
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: detailFont,
            .foregroundColor: UIColor.black
        ]
        
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        let details = [
            "Test Date: \(formatter.string(from: session.startTime))",
            "Duration: \(Int(session.endTime.timeIntervalSince(session.startTime))) minutes",
            "Device: \(session.deviceModel)",
            session.userAge != nil ? "User Age: \(session.userAge!) years" : "User Age: Not specified",
            "Gender: \(session.userGender?.rawValue.capitalized ?? "Not specified")"
        ]
        
        for (index, detail) in details.enumerated() {
            let detailRect = CGRect(x: 60, y: startY + 30 + CGFloat(index * 15), width: rect.width - 100, height: 15)
            detail.draw(in: detailRect, withAttributes: detailAttributes)
        }
        
        return currentY
    }
    
    private static func drawAudiograms(session: HearingTestSession, startY: CGFloat, in rect: CGRect) -> CGFloat {
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        
        let currentY = startY + 20
        "Audiogram Results".draw(in: CGRect(x: 40, y: currentY, width: 200, height: 25), withAttributes: titleAttributes)
        
        var yOffset = currentY + 40
        
        // Draw both ears
        for ear in [TestEar.right, TestEar.left] {
            let earResults = session.results(for: ear)
            if !earResults.isEmpty {
                yOffset = drawSimpleAudiogram(results: earResults, ear: ear, startY: yOffset, in: rect)
            }
        }
        
        return yOffset + 20
    }
    
    private static func drawSimpleAudiogram(results: [ThresholdResult], ear: TestEar, startY: CGFloat, in rect: CGRect) -> CGFloat {
        let earFont = UIFont.boldSystemFont(ofSize: 14)
        let earAttributes: [NSAttributedString.Key: Any] = [
            .font: earFont,
            .foregroundColor: UIColor.black
        ]
        
        "\(ear.displayName) Audiogram".draw(in: CGRect(x: 40, y: startY, width: 200, height: 20), withAttributes: earAttributes)
        
        // Simple table format since we can't draw complex charts in PDF easily
        let tableStartY = startY + 30
        let rowHeight: CGFloat = 20
        
        // Headers
        let headerFont = UIFont.boldSystemFont(ofSize: 10)
        let headerAttributes: [NSAttributedString.Key: Any] = [
            .font: headerFont,
            .foregroundColor: UIColor.black
        ]
        
        let headers = ["Frequency (Hz)", "Threshold (dB HL)", "Classification"]
        for (index, header) in headers.enumerated() {
            let headerRect = CGRect(x: 60 + CGFloat(index * 150), y: tableStartY, width: 140, height: rowHeight)
            header.draw(in: headerRect, withAttributes: headerAttributes)
        }
        
        // Data rows
        let dataFont = UIFont.systemFont(ofSize: 10)
        let dataAttributes: [NSAttributedString.Key: Any] = [
            .font: dataFont,
            .foregroundColor: UIColor.black
        ]
        
        for (rowIndex, result) in results.enumerated() {
            let rowY = tableStartY + rowHeight + CGFloat(rowIndex) * rowHeight
            let classification = ISO7029Calculator.classify(thresholdDB: result.thresholdDB)
            
            let rowData = [
                "\(result.frequencyHz)",
                "\(Int(result.thresholdDB))",
                classification.rawValue
            ]
            
            for (colIndex, data) in rowData.enumerated() {
                let dataRect = CGRect(x: 60 + CGFloat(colIndex * 150), y: rowY, width: 140, height: rowHeight)
                data.draw(in: dataRect, withAttributes: dataAttributes)
            }
        }
        
        // PTA if available
        let ptaResults = results.filter { [500, 1000, 2000, 4000].contains($0.frequencyHz) }
        if ptaResults.count == 4 {
            let pta = ptaResults.map { $0.thresholdDB }.reduce(0, +) / 4.0
            let ptaY = tableStartY + CGFloat(results.count + 1) * rowHeight + 10
            
            let ptaFont = UIFont.boldSystemFont(ofSize: 12)
            let ptaAttributes: [NSAttributedString.Key: Any] = [
                .font: ptaFont,
                .foregroundColor: UIColor.black
            ]
            
            "Pure Tone Average (PTA): \(Int(pta)) dB HL".draw(in: CGRect(x: 60, y: ptaY, width: 300, height: 15), withAttributes: ptaAttributes)
        }
        
        return tableStartY + CGFloat(results.count + 2) * rowHeight + 20
    }
    
    private static func drawDetailedResults(session: HearingTestSession, startY: CGFloat, in rect: CGRect) -> CGFloat {
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        
        "Detailed Analysis".draw(in: CGRect(x: 40, y: startY, width: 200, height: 25), withAttributes: titleAttributes)
        
        var currentY = startY + 40
        let detailFont = UIFont.systemFont(ofSize: 12)
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: detailFont,
            .foregroundColor: UIColor.black
        ]
        
        // Ear-by-ear analysis
        for ear in [TestEar.right, TestEar.left] {
            let classification = session.overallClassification(ear: ear)
            let pta = session.pureToneAverage(ear: ear)
            
            let earTitle = "\(ear.displayName): \(classification.rawValue)"
            let earTitleFont = UIFont.boldSystemFont(ofSize: 14)
            let earTitleAttributes: [NSAttributedString.Key: Any] = [
                .font: earTitleFont,
                .foregroundColor: UIColor.black
            ]
            
            earTitle.draw(in: CGRect(x: 60, y: currentY, width: 300, height: 20), withAttributes: earTitleAttributes)
            currentY += 25
            
            if let pta = pta {
                let ptaText = "Pure Tone Average: \(Int(pta)) dB HL"
                ptaText.draw(in: CGRect(x: 80, y: currentY, width: 300, height: 15), withAttributes: detailAttributes)
                currentY += 20
            }
            
            let description = classification.description
            let descriptionRect = CGRect(x: 80, y: currentY, width: rect.width - 120, height: 40)
            description.draw(in: descriptionRect, withAttributes: detailAttributes)
            currentY += 50
        }
        
        return currentY
    }
    
    private static func drawSafetyInformation(startY: CGFloat, in rect: CGRect) {
        let titleFont = UIFont.boldSystemFont(ofSize: 18)
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.black
        ]
        
        "Important Safety Information".draw(in: CGRect(x: 40, y: startY, width: 300, height: 25), withAttributes: titleAttributes)
        
        let safetyFont = UIFont.systemFont(ofSize: 11)
        let safetyAttributes: [NSAttributedString.Key: Any] = [
            .font: safetyFont,
            .foregroundColor: UIColor.black
        ]
        
        let safetyText = """
        • Sonaura is not a medical device and results are for educational/screening purposes only
        • For diagnosis or treatment of hearing conditions, consult a licensed audiologist
        • Results may vary based on device calibration and testing environment
        • Follow safe listening practices: keep volume below 85 dB for extended listening
        • Regular hearing assessments are recommended for monitoring hearing health
        """
        
        let safetyRect = CGRect(x: 60, y: startY + 30, width: rect.width - 100, height: 100)
        safetyText.draw(in: safetyRect, withAttributes: safetyAttributes)
    }
    
    private static func drawFooter(in rect: CGRect) {
        let footerFont = UIFont.systemFont(ofSize: 10)
        let footerAttributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: UIColor.gray
        ]
        
        let footerText = "Generated by Sonaura - Clinically-validated hearing assessment"
        let footerRect = CGRect(x: 40, y: rect.height - 30, width: rect.width - 80, height: 15)
        footerText.draw(in: footerRect, withAttributes: footerAttributes)
    }
    
    /// Save PDF to documents directory and return URL
    static func savePDFToDocuments(_ data: Data, filename: String) -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("\(filename).pdf")
        
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Failed to save PDF: \(error)")
            return nil
        }
    }
    
    /// Generate filename for test session
    static func generateFilename(for session: HearingTestSession) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let dateString = formatter.string(from: session.startTime)
        return "Sonaura_HearingTest_\(dateString)"
    }
}
