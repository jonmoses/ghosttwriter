import Foundation
import Testing
@testable import Ghostty

struct BrandingTests {
    @Test func bundleIdentifierIsGhosttwriter() {
        #expect(Bundle.main.bundleIdentifier?.hasPrefix("com.jonmoses.ghosttwriter") == true)
    }

    @Test func displayNameIsGhosttwriter() {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        #expect(name?.hasPrefix("Ghosttwriter") == true)
    }

    @Test func automaticUpdateChecksAreOff() {
        #expect(Bundle.main.object(forInfoDictionaryKey: "SUEnableAutomaticChecks") as? Bool == false)
    }
}
