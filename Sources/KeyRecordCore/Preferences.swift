import Foundation

public enum LayoutPreset: String, Codable, Sendable { case ansi, iso, alice, split, none }
public enum ProductLocale: String, Codable, Sendable { case english = "en", simplifiedChinese = "zh-Hans" }

public struct LayoutPreference: Equatable, Codable, Sendable {
    public let preset: LayoutPreset
    public let hasAsked: Bool
    public init(preset: LayoutPreset = .none, hasAsked: Bool = false) {
        self.preset = preset
        self.hasAsked = hasAsked
    }
}

/// Architecture §5.1: opaque ignored keys are preserved, not interpreted as a recommendation engine.
public struct Preferences: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = SchemaVersion.v1
    public let schemaVersion: SchemaVersion
    public let expectedCollecting: Bool
    public let currentCycleID: CycleID
    public let excludedBundleIDs: Set<String>
    public let ignoredRecommendationKeys: Set<String>
    public let layout: LayoutPreference
    public let loginItemEnabled: Bool
    public let locale: ProductLocale
    public let keyboardPoolConfirmed: Set<KeyCode>

    public init(
        currentCycleID: CycleID, expectedCollecting: Bool = false, excludedBundleIDs: Set<String> = [],
        ignoredRecommendationKeys: Set<String> = [], layout: LayoutPreference = LayoutPreference(),
        loginItemEnabled: Bool = false, locale: ProductLocale = .english, keyboardPoolConfirmed: Set<KeyCode> = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.currentCycleID = currentCycleID
        self.expectedCollecting = expectedCollecting
        self.excludedBundleIDs = excludedBundleIDs
        self.ignoredRecommendationKeys = ignoredRecommendationKeys
        self.layout = layout
        self.loginItemEnabled = loginItemEnabled
        self.locale = locale
        self.keyboardPoolConfirmed = keyboardPoolConfirmed
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, expectedCollecting, currentCycleID, excludedBundleIDs
        case ignoredRecommendationKeys, layout, loginItemEnabled, locale, keyboardPoolConfirmed
    }

    public init(from decoder: any Decoder) throws {
        let values = try strictContainer(decoder, keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(SchemaVersion.self, forKey: .schemaVersion)
        expectedCollecting = try values.decode(Bool.self, forKey: .expectedCollecting)
        currentCycleID = try values.decode(CycleID.self, forKey: .currentCycleID)
        excludedBundleIDs = try values.decode(Set<String>.self, forKey: .excludedBundleIDs)
        ignoredRecommendationKeys = try values.decode(Set<String>.self, forKey: .ignoredRecommendationKeys)
        layout = try values.decode(LayoutPreference.self, forKey: .layout)
        loginItemEnabled = try values.decode(Bool.self, forKey: .loginItemEnabled)
        locale = try values.decode(ProductLocale.self, forKey: .locale)
        keyboardPoolConfirmed = try values.decode(Set<KeyCode>.self, forKey: .keyboardPoolConfirmed)
    }
}
