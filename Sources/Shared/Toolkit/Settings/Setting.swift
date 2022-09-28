//
//  Copyright 2022 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Represents a single configurable property of a `Configurable` component and holds its current
/// `value`.
public class Setting<Value: Hashable>: Hashable {

    /// Unique identifier used to serialize `Preferences` to JSON.
    public let key: SettingKey

    /// Current value for this setting.
    public let value: Value

    /// JSON serializer for the `value`.
    let coder: SettingCoder<Value>

    /// Ensures the validity of a `value`.
    private let validator: SettingValidator<Value>

    /// Ensures that the condition required for this setting to be active are met in the given
    /// `Preferences` – e.g. another setting having a certain preference.
    private let activator: SettingActivator

    public init(
        key: SettingKey,
        value: Value,
        coder: SettingCoder<Value>,
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.key = key
        self.value = value
        self.coder = coder
        self.validator = validator
        self.activator = activator
    }

    public func validate(_ value: Value) -> Value? {
        validator(value)
    }

    public func decode(_ json: Any) -> Value? {
        coder.decode(json)
    }

    public func encode(_ value: Value) -> Any {
        coder.encode(value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(value)
    }

    public static func ==(lhs: Setting, rhs: Setting) -> Bool {
        if lhs === rhs {
            return true
        }

        return type(of: lhs) == type(of: rhs)
            && lhs.key == rhs.key
            && lhs.value == rhs.value
    }
}

extension Setting where Value == Bool {

    public convenience init(
        key: SettingKey,
        value: Bool,
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.init(key: key, value: value, coder: .literal(), validator: validator, activator: activator)
    }
}

extension Setting: SettingActivator {
    public func isActive(with preferences: Preferences) -> Bool {
        activator.isActive(with: preferences)
    }

    public func activate(in preferences: inout Preferences) {
        activator.activate(in: &preferences)
    }
}

/// Unique identifier used to serialize `Preferences` to JSON.
public struct SettingKey: Hashable {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    public static let backgroundColor = SettingKey("backgroundColor")
    public static let columnCount = SettingKey("columnCount")
    public static let fit = SettingKey("fit")
    public static let fontFamily = SettingKey("fontFamily")
    public static let fontSize = SettingKey("fontSize")
    public static let hyphens = SettingKey("hyphens")
    public static let imageFilter = SettingKey("imageFilter")
    public static let language = SettingKey("language")
    public static let letterSpacing = SettingKey("letterSpacing")
    public static let ligatures = SettingKey("ligatures")
    public static let lineHeight = SettingKey("lineHeight")
    public static let orientation = SettingKey("orientation")
    public static let pageMargins = SettingKey("pageMargins")
    public static let paragraphIndent = SettingKey("paragraphIndent")
    public static let paragraphSpacing = SettingKey("paragraphSpacing")
    public static let publisherStyles = SettingKey("publisherStyles")
    public static let readingProgression = SettingKey("readingProgression")
    public static let scroll = SettingKey("scroll")
    public static let spread = SettingKey("spread")
    public static let textAlign = SettingKey("textAlign")
    public static let textColor = SettingKey("textColor")
    public static let textNormalization = SettingKey("textNormalization")
    public static let theme = SettingKey("theme")
    public static let typeScale = SettingKey("typeScale")
    public static let verticalText = SettingKey("verticalText")
    public static let wordSpacing = SettingKey("wordSpacing")
}

/// Returns a valid value for the given `value`, if possible.
///
/// For example, a range setting will coerce the value to be in the range.
public typealias SettingValidator<Value> = (Value) -> Value?

/// A boolean `Setting`.
public typealias ToggleSetting = Setting<Bool>

/// A `Setting` whose value is constrained to a range.
public class RangeSetting<Value: Comparable & Hashable>: Setting<Value> {
    /// The valid range for the setting value.
    public let range: ClosedRange<Value>

    /// Value steps which can be used to decrement or increment the setting. It MUST be sorted in
    /// increasing order.
    public let suggestedSteps: [Value]?

    /// Suggested value increment which can be used to decrement or increment the setting.
    public let suggestedIncrement: Value?

    /// Returns a user-facing description for the given value. This can be used to format the value
    /// unit.
    public let formatValue: (Value) -> String

    public init(
        key: SettingKey,
        value: Value,
        range: ClosedRange<Value>,
        suggestedSteps: [Value]? = nil,
        suggestedIncrement: Value? = nil,
        formatValue: ((Value) -> String)? = nil,
        coder: SettingCoder<Value>,
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.range = range
        self.suggestedSteps = suggestedSteps
        self.suggestedIncrement = suggestedIncrement
        self.formatValue = formatValue ?? { value in
            (value as? NSNumber)
                .flatMap { rangeValueFormatter.string(from: $0) }
                ?? String(describing: value)
        }

        super.init(
            key: key, value: value, coder: coder,
            validator: { value in
                validator(value).flatMap { $0.clamped(to: range) }
            },
            activator: activator
        )
    }
}

extension RangeSetting where Value: Numeric {
    public convenience init(
        key: SettingKey,
        value: Value,
        range: ClosedRange<Value>,
        suggestedSteps: [Value]? = nil,
        suggestedIncrement: Value? = nil,
        formatValue: ((Value) -> String)? = nil,
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.init(
            key: key, value: value, range: range, suggestedSteps: suggestedSteps,
            suggestedIncrement: suggestedIncrement, formatValue: formatValue, coder: .literal(),
            validator: validator, activator: activator
        )
    }
}

private let rangeValueFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.maximumFractionDigits = 5
    return f
}()

/// A `RangeSetting` representing a percentage from 0.0 to 1.0.
public class PercentSetting: RangeSetting<Double> {
    public init(
        key: SettingKey,
        value: Double,
        range: ClosedRange<Double> = 0.0...1.0,
        suggestedSteps: [Double]? = nil,
        suggestedIncrement: Double? = 0.1,
        formatValue: ((Double) -> String)? = nil,
        validator: @escaping SettingValidator<Double> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        super.init(
            key: key, value: value, range: range, suggestedSteps: suggestedSteps,
            suggestedIncrement: suggestedIncrement,
            formatValue: formatValue ?? { value in
                percentValueFormatter.string(from: value as NSNumber)
                    ?? String(format: "%.0f%%", value * 100)
            },
            coder: .literal(),
            validator: validator,
            activator: activator
        )
    }
}

private let percentValueFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .percent
    f.minimumIntegerDigits = 1
    f.maximumIntegerDigits = 3
    f.maximumFractionDigits = 0
    return f
}()

/// A `Setting` whose value is a member of the enum `Value`.
public class EnumSetting<Value: Hashable>: Setting<Value> {

    /// List of valid values for this setting. Not all members of the enum are necessary supported.
    public let values: [Value]?

    /// Returns a user-facing description for the given value, when one is available.
    public let formatValue: (Value) -> String?

    public init(
        key: SettingKey,
        value: Value,
        values: [Value]?,
        formatValue: @escaping (Value) -> String? = { _ in nil },
        coder: SettingCoder<Value>,
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.values = values
        self.formatValue = formatValue
        super.init(
            key: key, value: value, coder: coder,
            validator: { value in
                guard values?.contains(value) ?? true else {
                    return nil
                }
                return validator(value)
            },
            activator: activator
        )
    }
}

extension EnumSetting where Value: RawRepresentable {

    public convenience init(
        key: SettingKey,
        value: Value,
        values: [Value]?,
        formatValue: @escaping (Value) -> String? = { _ in nil },
        validator: @escaping SettingValidator<Value> = { $0 },
        activator: SettingActivator = NullSettingActivator()
    ) {
        self.init(
            key: key, value: value, values: values, formatValue: formatValue,
            coder: .rawValue(), validator: validator, activator: activator
        )
    }
}