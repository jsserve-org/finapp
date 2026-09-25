import LocalAuthentication
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor @Observable
final class AppSecurityController {
    private static let pinAccount = "app-lock-pin"
    private let keychain: any SecretStoring
    private let defaults: UserDefaults
    var lockEnabled: Bool {
        didSet { defaults.set(lockEnabled, forKey: "ledgerly.privacy.lockEnabled") }
    }
    var biometricsEnabled: Bool {
        didSet { defaults.set(biometricsEnabled, forKey: "ledgerly.privacy.biometricsEnabled") }
    }
    var isLocked: Bool
    var privacyShieldVisible = false
    var unlockError: String?
    private var authenticating = false

    init(keychain: any SecretStoring = KeychainStore(), defaults: UserDefaults = .standard) {
        self.keychain = keychain
        self.defaults = defaults
        let hasPIN = keychain.secret(account: Self.pinAccount) != nil
        let enabled = hasPIN && defaults.bool(forKey: "ledgerly.privacy.lockEnabled")
        lockEnabled = enabled
        biometricsEnabled = enabled && defaults.bool(forKey: "ledgerly.privacy.biometricsEnabled")
        isLocked = enabled
    }

    var hasPIN: Bool { keychain.secret(account: Self.pinAccount) != nil }
    var biometricName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return switch context.biometryType {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .opticID: "Optic ID"
        default: "Biometrics"
        }
    }

    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        guard keychain.saveSecret(pin, account: Self.pinAccount) else { return false }
        lockEnabled = true
        isLocked = false
        unlockError = nil
        return true
    }

    func removePIN() {
        keychain.deleteSecret(account: Self.pinAccount)
        lockEnabled = false
        biometricsEnabled = false
        isLocked = false
    }

    func unlock(pin: String) -> Bool {
        guard pin == keychain.secret(account: Self.pinAccount) else {
            unlockError = "Incorrect PIN"
            return false
        }
        isLocked = false
        unlockError = nil
        return true
    }

    func lock() {
        if lockEnabled { isLocked = true }
    }

    func authenticateWithBiometrics() async {
        guard lockEnabled, biometricsEnabled, isLocked, !authenticating else { return }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Use PIN"
        do {
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
                unlockError = "\(biometricName) is unavailable. Use your PIN."
                return
            }
            if try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock your financial information") {
                isLocked = false
                unlockError = nil
            }
        } catch {
            unlockError = "Use your PIN to unlock Ledgerly."
        }
    }

    func becameActive() {
        privacyShieldVisible = false
        if isLocked && biometricsEnabled { Task { await authenticateWithBiometrics() } }
    }

    func resignedActive() {
        privacyShieldVisible = true
    }

    func enteredBackground() {
        privacyShieldVisible = true
        lock()
    }
}

@MainActor @Observable
final class ScreenshotNotificationController: NSObject {
    var showScreenshotNotice = false
    var notificationsEnabled: Bool {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "ledgerly.privacy.screenshotNotifications") }
    }

    override init() {
        notificationsEnabled = UserDefaults.standard.bool(forKey: "ledgerly.privacy.screenshotNotifications")
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
    }

    func setNotificationsEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            notificationsEnabled = granted
            return granted
        }
        notificationsEnabled = false
        return true
    }

    @objc private func screenshotTaken() {
        showScreenshotNotice = true
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Screenshot detected"
        content.body = "Ledgerly noticed a screenshot while financial information was visible."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct LedgerlyPrivacyRoot<Content: View>: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSecurityController.self) private var security
    @Environment(ScreenshotNotificationController.self) private var screenshots
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            content()
                .privacySensitive()
                .allowsHitTesting(!security.isLocked && !security.privacyShieldVisible)
                .accessibilityHidden(security.isLocked || security.privacyShieldVisible)
            if security.isLocked && !security.privacyShieldVisible {
                AppLockView()
                    .transition(.opacity)
                    .zIndex(2)
            }
            if security.privacyShieldVisible {
                PrivacyShieldView()
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: security.becameActive()
            case .inactive: security.resignedActive()
            case .background: security.enteredBackground()
            @unknown default: security.resignedActive()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in security.resignedActive() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in security.enteredBackground() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in security.becameActive() }
        .alert("Screenshot detected", isPresented: Binding(
            get: { screenshots.showScreenshotNotice },
            set: { screenshots.showScreenshotNotice = $0 }
        )) {
            Button("OK") { screenshots.showScreenshotNotice = false }
        } message: {
            Text("Ledgerly detected a screenshot. You can import banking screenshots from Settings → Screenshot Sync.")
        }
    }
}

private struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 42, weight: .semibold)).foregroundStyle(.tint)
                Text("Ledgerly").font(.title2.bold())
                Text("Financial information hidden").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ledgerly financial information hidden")
    }
}

private struct AppLockView: View {
    @Environment(AppSecurityController.self) private var security
    @State private var pin = ""

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 22) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(spacing: 6) {
                    Text("Ledgerly is locked").font(.title2.bold())
                    Text("Use \(security.biometricName) or enter your PIN.").font(.subheadline).foregroundStyle(.secondary)
                }
                SecureField("PIN", text: $pin)
                    .keyboardType(.numberPad)
                    .textContentType(.password)
                    .padding(12)
                    .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .frame(maxWidth: 280)
                    .onSubmit { unlock() }
                if let error = security.unlockError { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Unlock", action: unlock)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(pin.isEmpty)
                if security.biometricsEnabled {
                    Button("Use \(security.biometricName)", systemImage: "faceid") {
                        Task { await security.authenticateWithBiometrics() }
                    }
                }
            }
            .padding(28)
        }
    }

    private func unlock() {
        if security.unlock(pin: pin) { pin = "" }
    }
}

struct AppPrivacySettingsView: View {
    @Environment(AppSecurityController.self) private var security
    @Environment(ScreenshotNotificationController.self) private var screenshots
    @State private var showingPINSetup = false
    @State private var confirmingRemovePIN = false
    @State private var notificationMessage: String?

    var body: some View {
        Form {
            Section {
                if security.hasPIN {
                    Toggle("Lock on launch", isOn: Binding(get: { security.lockEnabled }, set: { security.lockEnabled = $0 }))
                    Toggle("Use \(security.biometricName)", isOn: Binding(get: { security.biometricsEnabled }, set: { security.biometricsEnabled = $0 }))
                        .disabled(!security.lockEnabled)
                    Button("Change PIN", systemImage: "number.square") { showingPINSetup = true }
                    Button("Lock now", systemImage: "lock.fill") { security.lock() }
                } else {
                    Button("Set up PIN", systemImage: "lock.fill") { showingPINSetup = true }
                }
            } header: { Text("App lock") } footer: {
                Text("Ledgerly hides financial information in Control Center and the app switcher. The PIN stays in this iPhone's Keychain.")
            }
            Section {
                Toggle("Screenshot notifications", isOn: Binding(
                    get: { screenshots.notificationsEnabled },
                    set: { enabled in Task {
                        let accepted = await screenshots.setNotificationsEnabled(enabled)
                        if enabled && !accepted { notificationMessage = "Notifications are disabled in iOS Settings." }
                    } }
                ))
            } footer: {
                Text("Ledgerly shows an in-app notice whenever iOS reports that a screenshot was taken. Optional notifications require iOS permission.")
            }
            if security.hasPIN {
                Section { Button("Remove PIN", systemImage: "lock.open", role: .destructive) { confirmingRemovePIN = true } }
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPINSetup) { PINSetupView() }
        .confirmationDialog("Remove the Ledgerly PIN?", isPresented: $confirmingRemovePIN, titleVisibility: .visible) {
            Button("Remove PIN", role: .destructive) { security.removePIN() }
        } message: { Text("Launch lock and biometric unlock will be turned off.") }
        .alert("Screenshot notifications", isPresented: Binding(get: { notificationMessage != nil }, set: { if !$0 { notificationMessage = nil } })) {
            Button("OK") { notificationMessage = nil }
        } message: { Text(notificationMessage ?? "") }
    }
}

private struct PINSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSecurityController.self) private var security
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("New PIN") {
                    SecureField("4–8 digit PIN", text: $pin).keyboardType(.numberPad)
                    SecureField("Confirm PIN", text: $confirmation).keyboardType(.numberPad)
                    if let error { Text(error).foregroundStyle(.red) }
                }
                Section { Text("Use a PIN you can remember. It cannot be recovered from the server.").foregroundStyle(.secondary) }
            }
            .navigationTitle("Set up PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(pin.isEmpty || confirmation.isEmpty) }
            }
        }
    }

    private func save() {
        guard (4...8).contains(pin.count), pin.allSatisfy(\.isNumber) else { error = "Use 4–8 digits."; return }
        guard pin == confirmation else { error = "PINs do not match."; return }
        guard security.setPIN(pin) else {
            error = "Ledgerly could not save the PIN securely. Reinstall or re-sign the app and try again."
            return
        }
        dismiss()
    }
}
