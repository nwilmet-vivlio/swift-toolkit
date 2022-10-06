//
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import R2Shared
import ReadiumInternal

/// Set of preferences used to update a `Configurable`'s settings.
///
/// `Preferences` can be serialized to JSON, which is useful to persist user preferences.
///
/// Usage example:
///
///     // Get the currently available settings for the configurable.
///     let settings = configurable.settings.value
///
///     // Build a new set of Preferences, using the Setting objects as keys.
///     var prefs = Preferences()
///     prefs.set(settings.scroll, false)
///     prefs.increment(settings.fontSize)
///
///     // Apply the preferences to the Configurable, which will automatically update its settings
///     // accordingly.
///     configurable.applyPreferences(prefs)
public struct Preferences: Hashable, Loggable {
    var values: JSONDictionary

    /// Creates a `Preferences` object using a mutable builder, for convenience.
    ///
    ///     let prefs = Preferences {
    ///         $0.set(settings.scroll, false)
    ///         $0.increment(settings.fontSize)
    ///     }
    public init(builder: (inout Preferences) -> Void) {
        self.init()
        builder(&self)
    }

    /// Creates a `Preferences` object from a JSON object.
    public init(json: [String: Any] = [:]) {
        self.values = JSONDictionary(json) ?? JSONDictionary()
    }

    /// Creates a `Preferences` object from a JSON object.
    public init(jsonString: String) throws {
        guard let json = try? JSONSerialization.jsonObject(with: jsonString.data(using: .utf8)!) as? [String: Any] else {
            throw JSONError.parsing(Preferences.self)
        }
        self.init(json: json)
    }

    /// Returns the JSON representation of this `Preferences`.
    public var json: [String: Any] {
        values.json
    }

    /// Returns the JSON representation of this `Preferences`.
    public var jsonString: String? {
        serializeJSONString(json)
    }

    /// Gets the preference for the given `setting`.
    public func get<Value>(_ setting: Setting<Value>) -> Value? {
        get(key: setting.key)
    }

    /// Gets the preference for the given setting `key` and `coder`.
    public func get<Value>(key: SettingKey<Value>) -> Value? {
        guard let value = values.json[key.id] else {
            return nil
        }
        return key.coder.decode(value)
    }

    /// Sets the preference for the given `setting`.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func set<Value>(_ setting: Setting<Value>, to preference: Value?, activate: Bool = true) {
        set(setting.key, to: preference)

        if preference != nil && activate {
            self.activate(setting)
        }
    }

    /// Sets the preference for the given setting `key`.
    public mutating func set<Value>(_ key: SettingKey<Value>, to preference: Value?) {
        if let preference = preference {
            values.json[key.id] = key.coder.encode(preference)
        } else {
            values.json.removeValue(forKey: key.id)
        }
    }

    /// Access the preference for the given `setting`.
    public subscript<Value>(setting: Setting<Value>) -> Value? {
        get {
            try? get(setting)
        }
        mutating set(newValue) {
            set(setting, to: newValue)
        }
    }

    /// Access the preference for the given setting `key`.
    public subscript<Value>(key: SettingKey<Value>) -> Value? {
        get {
            get(key: key)
        }
        mutating set(newValue) {
            set(key, to: newValue)
        }
    }

    /// Removes the preference for the given `setting`.
    public mutating func remove<Value>(_ setting: Setting<Value>?) {
        guard let setting = setting else {
            return
        }
        values.json.removeValue(forKey: setting.key.id)
    }

    /// Clears all preferences.
    public mutating func clear() {
        values.json.removeAll()
    }

    /// Merges the preferences of `other`, overwriting the ones from the receiver in case of
    /// conflict.
    public mutating func merge(_ other: Preferences) {
        values.json.merge(other.values.json, uniquingKeysWith: { _, n in n })
    }

    /// Returns whether the given `setting` is active in these preferences.
    ///
    /// An inactive setting is ignored by the `Configurable` until its activation conditions are met
    /// (e.g. another setting has a certain preference).
    public func isActive<Value>(_ setting: Setting<Value>) -> Bool {
        setting.isActive(with: self)
    }

    /// Activates the given `setting` in the preferences, if needed.
    public mutating func activate<Value>(_ setting: Setting<Value>) {
        guard !isActive(setting) else {
            return
        }
        setting.activate(in: &self)
    }

    /// Sets the preference for the given `setting` after transforming the current value.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func update<Value>(_ setting: Setting<Value>, activate: Bool = true, transform: (Value) -> Value) {
        set(setting, to: transform(prefOrValue(of: setting)), activate: activate)
    }

    /// Toggles the preference for the given `setting`.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func toggle(_ setting: Setting<Bool>, activate: Bool = true) {
        set(setting, to: !prefOrValue(of: setting), activate: activate)
    }

    /// Toggles the preference for the enum `setting` to the given `preference`.
    ///
    /// If the preference was already set to the same value, it is removed.
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func toggle<Value: Equatable>(_ setting: Setting<Value>, preference: Value, activate: Bool = true) {
        let current = try? get(setting)
        if current == nil || current! != preference {
            set(setting, to: preference, activate: activate)
        } else {
            remove(setting)
        }
    }

    /// Increments the preference for the given `setting` to the next step.
    ///
    /// If the `setting` doesn't have any suggested progression, the `next` function will be used
    /// instead to determine the next step.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func increment<Value>(_ setting: RangeSetting<Value>, activate: Bool = true, next: (Value) -> Value) {
        update(setting, activate: activate) { value in
            (setting.suggestedProgression?.increment(value) ?? next(value))
                .clamped(to: setting.range)
        }
    }

    /// Decrements the preference for the given `setting` to the previous step.
    ///
    /// If the `setting` doesn't have any suggested progression, the `previous` function will be
    /// used instead to determine the previous step.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func decrement<Value>(_ setting: RangeSetting<Value>, activate: Bool = true, previous: (Value) -> Value) {
        update(setting, activate: activate) { value in
            (setting.suggestedProgression?.decrement(value) ?? previous(value))
                .clamped(to: setting.range)
        }
    }

    /// Increments the preference for the given `setting` to the next step.
    ///
    /// The setting is incremented by the given `amount`, or falls back on the suggested progression
    /// or an increment of 1.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func increment(_ setting: RangeSetting<Int>, amount: Int? = nil, activate: Bool = true) {
        increment(setting, amount: amount, fallback: 1, activate: activate)
    }

    /// Decrements the preference for the given `setting` to the previous step.
    ///
    /// The setting is decremented by the given `amount`, or falls back on the suggested progression
    /// or an increment of 1.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func decrement(_ setting: RangeSetting<Int>, amount: Int? = nil, activate: Bool = true) {
        decrement(setting, amount: amount, fallback: 1, activate: activate)
    }

    /// Increments the preference for the given `setting` to the next step.
    ///
    /// The setting is incremented by the given `amount`, or falls back on the suggested progression
    /// or an increment of 0.1.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func increment(_ setting: RangeSetting<Double>, amount: Double? = nil, activate: Bool = true) {
        increment(setting, amount: amount, fallback: 0.1, activate: activate)
    }

    /// Decrements the preference for the given `setting` to the previous step.
    ///
    /// The setting is decremented by the given `amount`, or falls back on the suggested progression
    /// or an increment of 0.1.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func decrement(_ setting: RangeSetting<Double>, amount: Double? = nil, activate: Bool = true) {
        decrement(setting, amount: amount, fallback: 0.1, activate: activate)
    }

    private mutating func increment<Value: Numeric>(_ setting: RangeSetting<Value>, amount: Value?, fallback: Value, activate: Bool) {
        update(setting, activate: activate) { value in
            let newValue: Value = {
                if let amount = amount {
                    return value + amount
                } else if let progression = setting.suggestedProgression {
                    return progression.increment(value)
                } else {
                    return value + fallback
                }
            }()

            return newValue.clamped(to: setting.range)
        }
    }

    private mutating func decrement<Value: Numeric>(_ setting: RangeSetting<Value>, amount: Value?, fallback: Value, activate: Bool) {
        update(setting, activate: activate) { value in
            let newValue: Value = {
                if let amount = amount {
                    return value - amount
                } else if let progression = setting.suggestedProgression {
                    return progression.decrement(value)
                } else {
                    return value - fallback
                }
            }()

            return newValue.clamped(to: setting.range)
        }
    }

    /// Adjusts the preference for the given `setting` by adding `amount`.
    ///
    /// If `activate` is true, the setting will be force activated if needed.
    public mutating func adjustBy<Value: Numeric>(_ setting: RangeSetting<Value>, amount: Value, activate: Bool = true) {
        update(setting, activate: activate) {
            ($0 + amount).clamped(to: setting.range)
        }
    }

    /// Returns the preference for the given `Setting`, or its current value when missing.
    private func prefOrValue<Value>(of setting: Setting<Value>) -> Value {
        (try? get(setting)) ?? setting.value
    }
}

extension Preferences: CustomStringConvertible {
    public var description: String {
        "Preferences(\(json))"
    }
}