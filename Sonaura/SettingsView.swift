import SwiftUI

/// Settings view for app preferences and configuration
struct SettingsView: View {
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var showingDeleteAlert = false
    @State private var isWorksCitedExpanded = false
    
    private let worksCitedSections: [(title: String, entries: [String])] = [
        (
            title: "ISO Standards",
            entries: [
                "International Organization for Standardization. (2017). ISO 7029:2017 – Acoustics — Statistical distribution of hearing thresholds related to age and gender. ISO.",
                "International Organization for Standardization. (2024). ISO 7029:2017/Amd 1:2024 – Amendment 1: Correction of parameter values for estimating the hearing threshold distribution. ISO."
            ]
        ),
        (
            title: "Pure-Tone Audiometry Procedures",
            entries: [
                "British Society of Audiology. (2018). Recommended Procedure: Pure-tone air-conduction and bone-conduction threshold audiometry with and without masking. BSA.",
                "American National Standards Institute. (2018). ANSI/ASA S3.6–2018 – Specification for Audiometers. Acoustical Society of America."
            ]
        ),
        (
            title: "Age-Related Hearing Thresholds",
            entries: [
                "Chang, Y. S., Jeong, S. H., Kim, Y. H., & Lee, K. S. (2015). Hearing thresholds for a geriatric population composed of Korean adults. Clinical and Experimental Otorhinolaryngology, 8(3), 173–178.",
                "Theytaz, J., et al. (2023). Hearing thresholds for ‘otologically normal’ adults from the National Laboratory dataset. Journal of the Acoustical Society of America, 154(4), 2512–2525.",
                "Lee, J., Kim, H. J., et al. (2023). Hearing thresholds for unscreened U.S. adults: Data from NHANES 2015–2018. JAMA Otolaryngology—Head & Neck Surgery, 149(3), 223–231.",
                "Kim, G. H., et al. (2022). Re-estimated normal hearing threshold levels for pure tones using population-based data. International Journal of Audiology, 61(9), 700–709."
            ]
        ),
        (
            title: "Noise & Safe Listening",
            entries: [
                "Centers for Disease Control and Prevention / NIOSH. (2020). Noise-Induced Hearing Loss (NIHL): About NIOSH noise. U.S. Department of Health & Human Services.",
                "Centers for Disease Control and Prevention / NIOSH. (2020). Understanding Noise Exposure. U.S. Department of Health & Human Services.",
                "National Institute for Occupational Safety and Health. (1998). Criteria for a Recommended Standard: Occupational Noise Exposure. DHHS (NIOSH) Publication No. 98–126.",
                "World Health Organization. (2022). Safe listening: Questions and Answers. WHO.",
                "Rosenhall, U., et al. (2023). Why are noise exposure guidelines so complex? Frontiers in Public Health, 11, 1112294."
            ]
        ),
        (
            title: "Hearing Loss Definitions",
            entries: [
                "American Speech-Language-Hearing Association. (2020). Degree of Hearing Loss (Normal, Mild, Moderate, Severe, Profound). ASHA Publications.",
                "Northern, J. L., & Downs, M. P. (2014). Hearing in Children (6th ed.). Plural Publishing."
            ]
        ),
        (
            title: "Headphone Output & Consumer Audio",
            entries: [
                "Hearing Health Foundation. (2021). What Are Safe Decibels? HearingHealthFoundation.org.",
                "Better Hearing Institute. (2020). It’s a Loud World: Sound Advice for Healthy Hearing.",
                "Portnuff, C. D. F. (2016). Safe listening with personal music players. Journal of the Acoustical Society of America, 140(1), 61–66."
            ]
        ),
        (
            title: "Supporting Audiology Sources",
            entries: [
                "Shipton, M. S. (2022). Typical Hearing Thresholds – NPL Tables. University of Southampton.",
                "American Academy of Audiology. (2018). Clinical Practice Guidelines: Adult Hearing Screening. AAA."
            ]
        )
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 32) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(accentGradient)
                            
                            Text("Settings")
                                .font(.title.bold())
                                .foregroundStyle(.primary)
                        }
                        .padding(.top, 20)
                        
                        // About
                        aboutCard
                        
                        // Data Management
                        dataManagementCard
                        
                        worksCitedCard
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete All Test Data", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) {
                    dataManager.deleteAllTestSessions()
                }
            } message: {
                Text("This will permanently delete all stored test results. This action cannot be undone.")
            }
        }
    }
    
    private var dataManagementCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "internaldrive")
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text("Data Management")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            let storageInfo = dataManager.getStorageInfo()
            
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stored Tests")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(storageInfo.count) test\(storageInfo.count == 1 ? "" : "s") stored")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(storageInfo.totalSize)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(accentGradient)
                }
                
                if storageInfo.count > 0 {
                    Button(action: { showingDeleteAlert = true }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Delete All Test Data")
                        }
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text("About Sonaura")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(title: "Version", value: "1.0.0")
                InfoRow(title: "Build", value: "2025.1")
                InfoRow(title: "Platform", value: "iOS")
                
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("How your reading is produced:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        FeatureRow(text: "Hughson-Westlake staircase method")
                        FeatureRow(text: "ISO 7029 age-referenced norms")
                        FeatureRow(text: "ANSI S3.6 calibration standards")
                        FeatureRow(text: "NIOSH/WHO safety guidelines")
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why Sonaura?")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("We set out to make it easy to notice gradual change in your own hearing at home. Every tone, comparison, and safety check you see in the app ties directly back to peer-reviewed audiology standards.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    AboutHighlightRow(
                        icon: "waveform.circle.fill",
                        title: "How It Works",
                        message: "Pure-tone staircases sweep each ear from 250 Hz to 8 kHz (optionally 12 kHz), logging the hearing category per frequency in under five minutes."
                    )
                    
                    AboutHighlightRow(
                        icon: "figure.and.child.holdinghands",
                        title: "Personalized Benchmarks",
                        message: "ISO 7029 age- and gender-referenced norms show how your thresholds compare to peers and where any changes trend over time."
                    )
                    
                    AboutHighlightRow(
                        icon: "shield.lefthalf.fill",
                        title: "Safety First",
                        message: "Every presentation is capped at 80 dB HL and obeys WHO/NIOSH exposure limits. Ambient-noise checks pause testing if your space is too loud."
                    )
                    
                    AboutHighlightRow(
                        icon: "lock.doc.fill",
                        title: "Your Data",
                        message: "Test sessions stay on your device unless you export them. Delete all data anytime from this screen—no cloud account required."
                    )
                }
                
                Divider()
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    Text("Sonaura is not a medical device. It is built to help you notice change in your own hearing over time, not to diagnose it. For diagnosis or treatment, see a licensed audiologist.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var worksCitedCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isWorksCitedExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundStyle(accentGradient)
                        .font(.title2)
                    Text("How this works")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: isWorksCitedExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.headline)
                }
            }
            .buttonStyle(.plain)
            
            if isWorksCitedExpanded {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(worksCitedSections.indices, id: \.self) { index in
                        let section = worksCitedSections[index]
                        VStack(alignment: .leading, spacing: 12) {
                            Text(section.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(section.entries, id: \.self) { entry in
                                    CitationRow(text: entry)
                                }
                            }
                        }
                        
                        if index < worksCitedSections.count - 1 {
                            Divider()
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [SonauraColor.accent, SonauraColor.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct InfoRow: View {
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
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [SonauraColor.accent, SonauraColor.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct FeatureRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CitationRow: View {
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "record.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct AboutHighlightRow: View {
    let icon: String
    let title: String
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accentGradient)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [SonauraColor.accent, SonauraColor.accent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview {
    SettingsView()
}
