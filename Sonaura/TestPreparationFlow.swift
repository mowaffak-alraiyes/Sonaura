import SwiftUI
import AVFoundation

/// Duolingo-style multi-step test preparation flow
struct TestPreparationFlow: View {
    @EnvironmentObject var coordinator: HearingTestCoordinator
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var currentStep = 0
    @State private var showingTest = false
    @State private var isAnimating = false
    @State private var hasCheckedPermissions = false
    
    // Convenience access to view model and monitors through coordinator
    private var vm: HearingTestViewModel {
        coordinator.viewModel
    }
    
    // User input states
    @State private var userAge: Int?
    @State private var userGender: ISO7029Calculator.Gender = .male
    @State private var airPodsModel: AirPodsCalibration.ModelType = .airPodsPro
    @State private var includeExtendedHigh = false
    
    // Manual confirmations for readiness checklist
    @State private var airPodsConfirmed = false
    @State private var volumeConfirmed = false
    @State private var quietEnvironmentConfirmed = false
    
    // Settings from AppStorage
    @AppStorage("defaultAirPodsModel") private var defaultAirPodsModel: String = "AirPods Pro"
    @AppStorage("defaultIncludeExtendedHigh") private var defaultIncludeExtendedHigh: Bool = false
    
    private let totalSteps = 5
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Progress indicator
                    progressIndicator
                    
                    // Step content
                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(.easeInOut(duration: 0.5), value: currentStep)
                    
                    // Navigation buttons
                    navigationButtons
                        .padding(.bottom, 40)
                }
            }
            .navigationTitle("Test Preparation")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(currentStep > 0)
            .toolbar {
                if currentStep > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                currentStep -= 1
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            // Start noise monitoring when requirements step appears
            if currentStep == 2 { // Requirements step
                coordinator.startNoiseMonitoring()
            }
        }
        .fullScreenCover(isPresented: $showingTest) {
            TestFlowView(
                vm: vm,
                userAge: userAge,
                userGender: userGender,
                airPodsModel: airPodsModel,
                includeExtendedHigh: includeExtendedHigh
            )
        }
        .onAppear {
            // Load default settings
            if let defaultModel = AirPodsCalibration.ModelType.allCases.first(where: { $0.rawValue == defaultAirPodsModel }) {
                airPodsModel = defaultModel
            }
            includeExtendedHigh = defaultIncludeExtendedHigh
        }
    }
    
    private var progressIndicator: some View {
        VStack(spacing: 12) {
            // Progress bar
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(step <= currentStep ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color(.systemGray5)))
                        .frame(height: 8)
                        .animation(.easeInOut(duration: 0.3), value: currentStep)
                }
            }
            .padding(.horizontal, 24)
            
            // Step indicator
            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 32)
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            WelcomeStep()
        case 1:
            UserInfoStep(
                userAge: $userAge,
                userGender: $userGender,
                airPodsModel: $airPodsModel
            )
        case 2:
            RequirementsStep(
                hasCheckedPermissions: $hasCheckedPermissions,
                airPodsConfirmed: $airPodsConfirmed,
                volumeConfirmed: $volumeConfirmed,
                quietEnvironmentConfirmed: $quietEnvironmentConfirmed
            )
        case 3:
            ConfirmationStep(
                userAge: userAge,
                userGender: userGender,
                airPodsModel: airPodsModel,
                includeExtendedHigh: includeExtendedHigh
            )
        case 4:
            TestInstructionsStep(
                userAge: userAge,
                userGender: userGender,
                airPodsModel: airPodsModel,
                includeExtendedHigh: includeExtendedHigh
            )
        default:
            EmptyView()
        }
    }
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if currentStep < totalSteps - 1 {
                Button("Continue") {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentStep += 1
                    }
                }
                .font(.headline.weight(.medium))
                .foregroundStyle(canContinue ? .white : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canContinue ? AnyView(accentGradient) : AnyView(Color.gray.opacity(0.3)))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .disabled(!canContinue)
            }
            // Note: The final step (TestInstructionsStep) has its own "Begin Hearing Test" button
            // that actually starts the test, so we don't need a navigation button here
        }
        .padding(.horizontal, 24)
    }
    
    private var canContinue: Bool {
        switch currentStep {
        case 0: return true // Welcome step
        case 1: return userAge != nil && userAge! >= 18 && userAge! <= 100 // User info
        case 2: return requirementChecklistReady
        case 3: return true // Confirmation
        case 4: return true // Test instructions
        default: return false
        }
    }
    
    private var requirementChecklistReady: Bool {
        // All 3 checkboxes must be manually checked by the user
        return airPodsConfirmed && volumeConfirmed && quietEnvironmentConfirmed
    }
    
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - Step Views

struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 24) {
            // Icon and title
            VStack(spacing: 20) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 100))
                    .foregroundStyle(accentGradient)
                
                VStack(spacing: 12) {
                    Text("Welcome to Sonaura")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text("Let's prepare your hearing test with clinically-validated methods")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                }
            }
            .padding(.top, 20)
            
            // Features list
            VStack(alignment: .leading, spacing: 16) {
                FeatureItem(icon: "checkmark.shield.fill", text: "Clinically-validated Hughson-Westlake method")
                FeatureItem(icon: "chart.line.uptrend.xyaxis", text: "Age-matched hearing comparisons")
                FeatureItem(icon: "headphones", text: "Calibrated for AirPods")
                FeatureItem(icon: "shield.fill", text: "Safe listening guidelines")
            }
            .padding(.horizontal, 24)
            
            Spacer()
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

struct UserInfoStep: View {
    @Binding var userAge: Int?
    @Binding var userGender: ISO7029Calculator.Gender
    @Binding var airPodsModel: AirPodsCalibration.ModelType
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(accentGradient)
                    
                    VStack(spacing: 8) {
                        Text("Your Information")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("This helps us compare your results to age-matched norms")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 40)
                
                // Input fields
                VStack(spacing: 24) {
                    // Age input
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Age")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your age", value: $userAge, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .frame(height: 50)
                        
                        Text("Ages 18-100 for best comparison accuracy")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // Gender selection
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Gender")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Picker("Gender", selection: $userGender) {
                            Text("Male").tag(ISO7029Calculator.Gender.male)
                            Text("Female").tag(ISO7029Calculator.Gender.female)
                        }
                        .pickerStyle(.segmented)
                        
                        Text("Hearing norms vary slightly by gender")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    // AirPods model
                    VStack(alignment: .leading, spacing: 12) {
                        Text("AirPods Model")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                        
                        Picker("AirPods Model", selection: $airPodsModel) {
                            ForEach(AirPodsCalibration.ModelType.allCases, id: \.self) { model in
                                Text(model.rawValue).tag(model)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(height: 50)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Text("Select your AirPods model for accurate calibration")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
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
}

struct RequirementsStep: View {
    @EnvironmentObject var coordinator: HearingTestCoordinator
    @Binding var hasCheckedPermissions: Bool
    @Binding var airPodsConfirmed: Bool
    @Binding var volumeConfirmed: Bool
    @Binding var quietEnvironmentConfirmed: Bool
    @State private var showingPermissionAlert = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(accentGradient)
                    
                    VStack(spacing: 8) {
                        Text("Test Requirements")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Please verify each requirement and check the boxes when ready")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 40)
                
                VStack(spacing: 20) {
                    RequirementChecklistItem(
                        icon: "earbuds",
                        title: "Headphones Connected",
                        description: "Connect your AirPods or Bluetooth headphones",
                        statusText: airPodsReady ? "Connected" : "Connect Now",
                        statusColor: airPodsReady ? .green : .orange,
                        accentGradient: accentGradient,
                        isEnabled: true, // Always allow manual checking
                        isChecked: $airPodsConfirmed
                    )
                    
                    RequirementChecklistItem(
                        icon: "speaker.wave.3.fill",
                        title: "Volume at Maximum",
                        description: "Set your iPhone volume to 100% for accurate calibration",
                        statusText: volumeReady ? "At Maximum" : "Raise Volume",
                        statusColor: volumeReady ? .green : .orange,
                        accentGradient: accentGradient,
                        isEnabled: true, // Always allow manual checking
                        isChecked: $volumeConfirmed
                    )
                    
                    RequirementChecklistItem(
                        icon: "mic.fill",
                        title: "Quiet Environment",
                        description: "Find a quiet room for accurate testing",
                        statusText: quietStatusText,
                        statusColor: quietStatusColor,
                        accentGradient: accentGradient,
                        isEnabled: true, // Always allow manual checking
                        isChecked: $quietEnvironmentConfirmed,
                        action: noiseAction
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .alert("Microphone Permission Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Sonaura needs microphone access to check ambient noise levels. Please enable microphone permissions in Settings.")
        }
    }
    
    private var airPodsReady: Bool {
        coordinator.routeMonitor.isHeadphoneLikeConnected
    }
    
    private var volumeReady: Bool {
        coordinator.volumeMonitor.outputVolume >= 0.99
    }
    
    private var quietReady: Bool {
        coordinator.noiseMonitor.isQuietEnough && hasCheckedPermissions
    }
    
    private var quietStatusText: String {
        if !hasCheckedPermissions {
            return "Check Noise"
        }
        return quietReady ? "Quiet Enough" : "Too Noisy"
    }
    
    private var quietStatusColor: Color {
        quietReady ? .green : .orange
    }
    
    private var noiseAction: (() -> Void)? {
        guard !quietReady else { return nil }
        return {
            checkMicrophonePermissionsAndNoise()
        }
    }
    
    private func checkMicrophonePermissionsAndNoise() {
        // Check microphone permission status using legacy API
        let permission = AVAudioSession.sharedInstance().recordPermission
        switch permission {
        case .granted:
            hasCheckedPermissions = true
            coordinator.startNoiseMonitoring()
        case .denied, .undetermined:
            // Request permission
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if granted {
                        hasCheckedPermissions = true
                        coordinator.startNoiseMonitoring()
                    } else {
                        showingPermissionAlert = true
                    }
                }
            }
        @unknown default:
            showingPermissionAlert = true
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

struct ConfirmationStep: View {
    let userAge: Int?
    let userGender: ISO7029Calculator.Gender
    let airPodsModel: AirPodsCalibration.ModelType
    let includeExtendedHigh: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                    
                    VStack(spacing: 8) {
                        Text("Ready to Start")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Please review your information before beginning the test")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 40)
                
                // Confirmation details
                VStack(spacing: 20) {
                    ConfirmationItem(
                        icon: "person.circle",
                        title: "Personal Information",
                        details: [
                            "Age: \(userAge ?? 0) years",
                            "Gender: \(userGender.rawValue.capitalized)",
                            "AirPods: \(airPodsModel.rawValue)"
                        ]
                    )
                    
                    ConfirmationItem(
                        icon: "waveform",
                        title: "Test Configuration",
                        details: [
                            "Frequencies: 250, 500, 1000, 2000, 4000, 8000 Hz" + (includeExtendedHigh ? ", 12 kHz" : ""),
                            "Test steps: \(includeExtendedHigh ? "14" : "12") (both ears)",
                            "Method: 4-level screening ladder",
                            "Duration: ~3-5 minutes"
                        ]
                    )
                    
                    ConfirmationItem(
                        icon: "info.circle",
                        title: "How the Test Works",
                        details: [
                            "Each frequency tests 4 screening levels (15-55 dB HL)",
                            "Press 'Play Sound' to hear each tone",
                            "Respond 'Heard It' or 'Didn't Hear' honestly",
                            "This is a clinically-validated screening method"
                        ]
                    )
                    
                    ConfirmationItem(
                        icon: "shield.fill",
                        title: "Safety Information",
                        details: [
                            "Maximum test level: 55 dB HL (screening range)",
                            "Brief 0.5-second tone presentations",
                            "Safe for all users - well below harmful levels",
                            "Consult audiologist for concerns"
                        ]
                    )
                }
                .padding(.horizontal, 24)
                
                // Disclaimer
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.title3)
                    Text("Sonaura is not a medical device. Results are for educational and screening purposes only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }
}

// MARK: - Helper Views

struct FeatureItem: View {
    let icon: String
    let text: String
    
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
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

struct RequirementChecklistItem: View {
    let icon: String
    let title: String
    let description: String
    let statusText: String
    let statusColor: Color
    let accentGradient: LinearGradient
    let isEnabled: Bool
    @Binding var isChecked: Bool
    var action: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            iconView
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusControl
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            checkbox
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            // Always allow manual checking
            isChecked.toggle()
            // Also execute action if provided (e.g., for noise check)
            action?()
        }
    }
    
    @ViewBuilder
    private var statusControl: some View {
        if let action = action {
            Button(action: action) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
            .buttonStyle(.plain)
        } else {
            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
    }
    
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: 52, height: 52)
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accentGradient)
        }
    }
    
    private var checkbox: some View {
        Button {
            // Always allow manual checking
            isChecked.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                if isChecked {
                    Circle()
                        .fill(accentGradient)
                        .frame(width: 32, height: 32)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .stroke(accentGradient, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) checklist")
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
    }
}

struct RequirementStatusItem: View {
    let icon: String
    let title: String
    let description: String
    let statusText: String
    let statusColor: Color
    let accentGradient: LinearGradient
    let isPositive: Bool
    var action: (() -> Void)?
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            iconView
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    statusBadge
                }
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .onTapGesture {
            if let action, !isPositive {
                action()
            }
        }
    }
    
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: 52, height: 52)
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(accentGradient)
        }
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: isPositive ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(statusColor)
            
            if let action = action, !isPositive {
                Button(action: action) {
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }
        }
    }
}

struct ConfirmationItem: View {
    let icon: String
    let title: String
    let details: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(accentGradient)
                    .font(.title2)
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(details, id: \.self) { detail in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
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
}

struct TestFlowView: View {
    @ObservedObject var vm: HearingTestViewModel
    let userAge: Int?
    let userGender: ISO7029Calculator.Gender
    let airPodsModel: AirPodsCalibration.ModelType
    let includeExtendedHigh: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dataManager = HearingTestDataManager()
    @State private var isSaved = false
    @State private var showSaveSuccess = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    if vm.isRunning {
                        testInProgressView
                    } else if let session = vm.testSession {
                        resultsView(session: session)
                    } else {
                        Text("Preparing test...")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(24)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Sonaura Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Exit") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            vm.userAge = userAge
            vm.userGender = userGender
            vm.airPodsModel = airPodsModel
            vm.includeExtendedHigh = includeExtendedHigh
            
            // Check if this session is already saved
            if let session = vm.testSession {
                checkIfSaved(session: session)
            }
            
            // Start test after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                vm.startTest()
            }
        }
        .onChange(of: vm.testSession) { _, newSession in
            if let session = newSession {
                checkIfSaved(session: session)
            }
        }
        .overlay {
            if showSaveSuccess {
                VStack {
                    Spacer()
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                        Text("Results saved to Test History")
                            .foregroundStyle(.white)
                            .font(.headline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 8)
                    .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showSaveSuccess)
            }
        }
    }
    
    // Duolingo-style test interface
    private var testInProgressView: some View {
        VStack(spacing: 0) {
            // Progress indicator - centered like reference image// notch
            VStack(spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(0..<vm.steps.count, id: \.self) { step in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(step <= vm.currentStepIndex ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color(.systemGray4)))
                            .frame(width: 24, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: vm.currentStepIndex)
                    }
                }
                .padding(.horizontal, 24)
                
                Text("Step \(vm.currentStepIndex + 1) of \(vm.steps.count)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 120)
            .padding(.bottom, 24)

            if let step = vm.currentStep {
                VStack(spacing: 0) {
                    // Main instruction - Duolingo style
                    Text("Listen for the tone and respond when you hear it")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    
                    // Wavelength logo
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(accentGradient)
                        .padding(.bottom, 24)
                    
                    // Hz + dB display - clean without background
                    VStack(spacing: 32) {
                        // Frequency display
                        VStack(spacing: 16) {
                            HStack {
                                Image(systemName: "speaker.wave.2.fill")
                                    .foregroundStyle(accentGradient)
                                    .font(.title2)
                                
                                Text("\(step.frequencyHz) Hz")
                                    .font(.system(size: 42, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }
                            
                            Text(step.ear.displayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                            
                            // Show current dB level being tested (especially important when level changes)
                            if vm.hasPlayedCurrentTone {
                                Text("Testing at \(Int(vm.currentPresentationLevel)) dB HL")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            }
                        }
                        
                        // Status indicator - smaller
                        if vm.isWaitingForResponse {
                            HStack(spacing: 8) {
                                Image(systemName: "ear.fill")
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                                Text("Please respond now")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(accentGradient)
                            .clipShape(Capsule())
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                                Text(vm.currentInstructions.isEmpty ? "Press 'Play Sound' to hear the tone" : vm.currentInstructions)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 30)
                            .background(accentGradient)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 15)
                    
                    Spacer(minLength: 5)
                    
                    // Response buttons - improved layout
                    VStack(spacing: 16) {
                        // Play Sound button - smaller
                        Button(action: { vm.playSound() }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                Text("Play Sound")
                                    .font(.title3.weight(.bold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(accentGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .disabled(vm.hasPlayedCurrentTone && vm.isWaitingForResponse)
                        .opacity((vm.hasPlayedCurrentTone && vm.isWaitingForResponse) ? 0.6 : 1.0)
                        .padding(.horizontal, 24)
                        
                        // Response buttons - more compact
                        HStack(spacing: 12) {
                            Button(action: {
                                vm.recordResponse(heard: false)
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title3)
                                    Text("Didn't Hear")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(
                                    colors: [Color.red, Color.red.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .red.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                            .disabled(!vm.isWaitingForResponse)
                            
                            Button(action: {
                                vm.recordResponse(heard: true)
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                    Text("Heard It")
                                        .font(.subheadline.weight(.bold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(LinearGradient(
                                    colors: [Color.green, Color.green.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .shadow(color: .green.opacity(0.3), radius: 3, x: 0, y: 1)
                            }
                            .disabled(!vm.isWaitingForResponse)
                        }
                        .padding(.horizontal, 24)
                        .opacity(vm.hasPlayedCurrentTone ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.2), value: vm.hasPlayedCurrentTone)
                        .allowsHitTesting(vm.hasPlayedCurrentTone) // Only allow interaction when visible
                    }
                    .padding(.bottom, 90)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
    }
    
    private var accentGradient: LinearGradient {
        LinearGradient(
            colors: [Color.blue, Color.purple],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
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
                
                // Summary cards with percentiles
                ForEach([TestEar.right, TestEar.left], id: \.self) { ear in
                    earResultCard(session: session, ear: ear)
                }
                
                // Action buttons
                VStack(spacing: 16) {
                    // Save Results button
                    Button(action: {
                        saveResults(session: session)
                    }) {
                        HStack {
                            Image(systemName: isSaved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            Text(isSaved ? "Saved to History" : "Save Results Locally")
                        }
                        .font(.headline.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isSaved ? AnyShapeStyle(Color.green) : AnyShapeStyle(accentGradient))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(isSaved)
                    
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
                    
                    Button(action: {
                        vm.restart()
                        dismiss()
                    }) {
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
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
    
    // MARK: - Results Helper Views
    
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
                        explanation: "Percentiles compare your hearing to others your age and gender. 'Worse than 80%' means your hearing is worse than 80% of people your age. Lower percentiles = better hearing."
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
    
    private func checkIfSaved(session: HearingTestSession) {
        // Check if this session ID already exists in saved sessions
        let existingSession = dataManager.testSessions.first { $0.id == session.id }
        isSaved = existingSession != nil
    }
    
    private func saveResults(session: HearingTestSession) {
        // Prevent duplicate saves
        guard !isSaved else { return }
        
        dataManager.saveTestSession(session)
        isSaved = true
        showSaveSuccess = true
        
        // Hide success message after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showSaveSuccess = false
        }
    }
    
    private func exportPDF(for session: HearingTestSession) {
        print("📄 Starting PDF export...")
        let pdfData = PDFExporter.generatePDF(for: session)
        let filename = PDFExporter.generateFilename(for: session)
        
        print("📄 PDF generated: \(pdfData.count) bytes, filename: \(filename)")
        
        guard let url = PDFExporter.savePDFToDocuments(pdfData, filename: filename) else {
            print("❌ Failed to save PDF to documents directory")
            return
        }
        
        print("✅ PDF saved to: \(url.path)")
        
        // Present share sheet on main thread
        DispatchQueue.main.async {
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            
            // For iPad support
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                
                // Find the topmost view controller
                var topVC = window.rootViewController
                while let presented = topVC?.presentedViewController {
                    topVC = presented
                }
                
                guard let presentingVC = topVC else {
                    print("❌ Could not find presenting view controller")
                    return
                }
                
                // Configure popover for iPad
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
                
                presentingVC.present(activityVC, animated: true) {
                    print("✅ Share sheet presented successfully")
                }
            } else {
                print("❌ Could not access window scene")
            }
        }
    }
}

struct TestInstructionsStep: View {
    let userAge: Int?
    let userGender: ISO7029Calculator.Gender
    let airPodsModel: AirPodsCalibration.ModelType
    let includeExtendedHigh: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingTest = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header
                VStack(spacing: 20) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 100))
                        .foregroundStyle(accentGradient)
                    
                    VStack(spacing: 12) {
                        Text("How the Test Works")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        
                        Text("Understanding the Sonaura hearing test process")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.top, 40)
                
                // Instructions content
                VStack(spacing: 24) {
                    // What to expect
                    InstructionCard(
                        icon: "ear.trianglebadge.exclamationmark",
                        title: "What to Expect",
                        description: "You'll test \(includeExtendedHigh ? "14" : "12") frequencies across both ears (250 Hz to 8000 Hz\(includeExtendedHigh ? ", plus 12 kHz" : "")). Each frequency uses a 4-level screening method to quickly assess your hearing.",
                        color: .blue
                    )
                    
                    // How to respond
                    InstructionCard(
                        icon: "hand.raised.fill",
                        title: "How to Respond",
                        description: "Press 'Play Sound' to hear each tone. If you hear it, tap 'Heard It'. If you don't hear it, tap 'Didn't Hear'. Be honest - there are no wrong answers. The test will automatically try different volume levels.",
                        color: .green
                    )
                    
                    // Test method
                    InstructionCard(
                        icon: "chart.bar.fill",
                        title: "4-Level Screening",
                        description: "Each frequency tests 4 volume levels (15, 25, 40, and 55 dB HL) to quickly determine your hearing range. This is a clinically-validated screening method used for rapid hearing assessment.",
                        color: .orange
                    )
                    
                    // Test duration
                    InstructionCard(
                        icon: "clock.fill",
                        title: "Test Duration",
                        description: "The test takes about 3-5 minutes total. You'll test both ears at \(includeExtendedHigh ? "7" : "6") frequencies each. You can take breaks between frequencies if needed.",
                        color: .purple
                    )
                }
                .padding(.horizontal, 24)
                
                // Start button
                Button(action: {
                    showingTest = true
                }) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                        Text("Begin Sonaura Test")
                    }
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showingTest) {
            TestFlowView(
                vm: HearingTestViewModel(),
                userAge: userAge,
                userGender: userGender,
                airPodsModel: airPodsModel,
                includeExtendedHigh: includeExtendedHigh
            )
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

struct InstructionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)
                
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            
            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    TestPreparationFlow()
        .environmentObject(HearingTestCoordinator())
}
