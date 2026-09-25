import Foundation
import UIKit
import XCTest
@testable import Ledgerly

@MainActor
final class AppPrivacyTests: XCTestCase {
    func testPINUnlockRejectsIncorrectPINAndAcceptsCorrectPIN() {
        let (keychain, defaults, suiteName) = fixture()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let security = AppSecurityController(keychain: keychain, defaults: defaults)
        security.setPIN("2468")
        security.lock()

        XCTAssertFalse(security.unlock(pin: "1357"))
        XCTAssertTrue(security.isLocked)
        XCTAssertEqual(security.unlockError, "Incorrect PIN")

        XCTAssertTrue(security.unlock(pin: "2468"))
        XCTAssertFalse(security.isLocked)
        XCTAssertNil(security.unlockError)
    }

    func testBackgroundLocksAndShowsPrivacyShield() {
        let (keychain, defaults, suiteName) = fixture()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let security = AppSecurityController(keychain: keychain, defaults: defaults)
        security.setPIN("2468")
        security.enteredBackground()

        XCTAssertTrue(security.isLocked)
        XCTAssertTrue(security.privacyShieldVisible)

        security.becameActive()
        XCTAssertFalse(security.privacyShieldVisible)
        XCTAssertTrue(security.isLocked)
    }

    func testLockPreferenceAndPINSurviveControllerRecreation() {
        let (keychain, defaults, suiteName) = fixture()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let original = AppSecurityController(keychain: keychain, defaults: defaults)
        original.setPIN("8642")

        let restored = AppSecurityController(keychain: keychain, defaults: defaults)
        XCTAssertTrue(restored.hasPIN)
        XCTAssertTrue(restored.lockEnabled)
        XCTAssertTrue(restored.isLocked)
        XCTAssertTrue(restored.unlock(pin: "8642"))
    }

    func testRemovingPINDisablesLockAndBiometrics() {
        let (keychain, defaults, suiteName) = fixture()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let security = AppSecurityController(keychain: keychain, defaults: defaults)
        security.setPIN("2468")
        security.biometricsEnabled = true
        security.removePIN()

        XCTAssertFalse(security.hasPIN)
        XCTAssertFalse(security.lockEnabled)
        XCTAssertFalse(security.biometricsEnabled)
        XCTAssertFalse(security.isLocked)
    }

    func testFailedSecureStorageDoesNotEnableLock() {
        let (_, defaults, suiteName) = fixture()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let security = AppSecurityController(keychain: RejectingSecretStore(), defaults: defaults)

        XCTAssertFalse(security.setPIN("2468"))
        XCTAssertFalse(security.hasPIN)
        XCTAssertFalse(security.lockEnabled)
        XCTAssertFalse(security.isLocked)
    }

    func testScreenshotNotificationShowsInAppNotice() {
        let screenshots = ScreenshotNotificationController()
        XCTAssertFalse(screenshots.showScreenshotNotice)

        NotificationCenter.default.post(name: UIApplication.userDidTakeScreenshotNotification, object: nil)

        XCTAssertTrue(screenshots.showScreenshotNotice)
    }

    private func fixture() -> (MemorySecretStore, UserDefaults, String) {
        let suiteName = "com.ledgerly.tests.\(UUID().uuidString)"
        return (MemorySecretStore(), UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

private final class MemorySecretStore: SecretStoring {
    private var values: [String: String] = [:]

    func secret(account: String) -> String? { values[account] }
    func saveSecret(_ value: String, account: String) -> Bool {
        values[account] = value
        return true
    }
    func deleteSecret(account: String) { values.removeValue(forKey: account) }
}

private struct RejectingSecretStore: SecretStoring {
    func secret(account: String) -> String? { nil }
    func saveSecret(_ value: String, account: String) -> Bool { false }
    func deleteSecret(account: String) {}
}
