import Foundation

// MARK: - Generic JSON value

/// Any JSON value. Used where the spec allows more than one type
/// (a setting's default, a select option's value, a component's value).
public enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

// MARK: - Box (lets a struct hold an optional value of its own type)

public final class Box<Wrapped: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    public let value: Wrapped

    public init(_ value: Wrapped) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        value = try decoder.singleValueContainer().decode(Wrapped.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }

    public static func == (lhs: Box<Wrapped>, rhs: Box<Wrapped>) -> Bool {
        lhs.value == rhs.value
    }
}

// MARK: - Top level

public enum WidgetSize: String, Codable, Sendable, Equatable {
    case small, medium, large
}

public enum WidgetPlatform: String, Codable, Sendable, Equatable {
    case macos, ios
}

/// A complete widget file. (Named `WidgetDefinition` so it does not clash with the module name.)
public struct WidgetDefinition: Codable, Sendable, Equatable {
    public let schema: String?
    public let spec: String
    public let id: String
    public let name: String
    public let description: String?
    public let version: String
    public let author: String?
    /// An SF Symbol name the host shows beside the widget's title.
    public let symbol: String?
    public let sizes: [WidgetSize]?
    public let platforms: [WidgetPlatform]?
    public let permissions: WidgetPermissions?
    public let settings: [WidgetSetting]?
    public let data: [String: WidgetDataSource]?
    /// Component tree per size. "default" is the fallback.
    public let view: [String: WidgetComponent]

    enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case spec, id, name, description, version, author, symbol
        case sizes, platforms, permissions, settings, data, view
    }
}

// MARK: - Permissions

public struct WidgetPermissions: Codable, Sendable, Equatable {
    public let network: [String]?
    public let system: [String]?
    public let ai: Bool?
    public let commands: Bool?
    public let files: [String]?
}

// MARK: - Settings

public enum WidgetSettingType: String, Codable, Sendable, Equatable {
    case string, number, boolean, select, color, stringList, secret
}

public struct WidgetSettingOption: Codable, Sendable, Equatable {
    public let value: JSONValue
    public let label: String
}

public struct WidgetSetting: Codable, Sendable, Equatable {
    public let key: String
    public let type: WidgetSettingType
    public let label: String
    public let defaultValue: JSONValue?
    public let options: [WidgetSettingOption]?
    public let min: Double?
    public let max: Double?
    public let help: String?

    enum CodingKeys: String, CodingKey {
        case key, type, label, options, min, max, help
        case defaultValue = "default"
    }
}

// MARK: - Data sources

public enum WidgetDataSourceType: String, Codable, Sendable, Equatable {
    case `static`, time, http, rss, system, ai
    /// Reads from the app's local store. Needs no network permission. Spec 0.2.
    case query
}

/// Conditions for a `query` source. Strings may contain `{{ }}` expressions, so a setting can drive them.
public struct WidgetQueryFilter: Codable, Sendable, Equatable {
    /// A subject area: "all" or "ai".
    public let subject: String?
    /// Only stories tagged with one of these companies, technologies or topics.
    public let entities: [String]?
    /// Only stories of these kinds (shipping, announcement, research, ...).
    public let kinds: [String]?
    /// Only stories active within this many hours.
    public let sinceHours: Double?
    /// Only stories the user saved or marked as favourite.
    public let saved: Bool?
    /// repositories: only those written mainly in this language. Empty means any.
    public let language: String?
    /// stories: one of the app's own lists ("overview", "ai", "latest", "saved") or "folder:<name>".
    /// Decides the filter and the order together, so a setting can switch a widget between them.
    public let view: String?

    public init(subject: String? = nil, entities: [String]? = nil, kinds: [String]? = nil, sinceHours: Double? = nil, saved: Bool? = nil, language: String? = nil, view: String? = nil) {
        self.view = view
        self.language = language
        self.subject = subject
        self.entities = entities
        self.kinds = kinds
        self.sinceHours = sinceHours
        self.saved = saved
    }
}

public struct WidgetDataSource: Codable, Sendable, Equatable {
    public let type: WidgetDataSourceType
    public let refresh: String?
    public let value: JSONValue?
    public let url: String?
    public let method: String?
    public let headers: [String: String]?
    public let path: String?
    public let each: String?
    /// Name of the loop variable for `each` (JSON key: "as").
    public let loopVariable: String?
    public let map: [String: String]?
    public let limit: Int?
    public let kind: String?
    public let input: String?
    public let prompt: String?
    public let cache: String?
    public let maxTokens: Int?
    /// query: which collection to read: "stories" or "repositories".
    public let from: String?
    /// query: conditions (JSON key: "where").
    public let filter: WidgetQueryFilter?
    /// query: "rank" (most important first) or "latest".
    public let sort: String?

    enum CodingKeys: String, CodingKey {
        case type, refresh, value, url, method, headers, path, each, map, limit
        case kind, input, prompt, cache, maxTokens, from, sort
        case loopVariable = "as"
        case filter = "where"
    }
}

// MARK: - Components

public enum WidgetComponentType: String, Codable, Sendable, Equatable {
    case vstack, hstack, zstack, spacer, divider
    case text, number, image, icon, progress, chart, list, badge, button
}

public enum WidgetTextSize: String, Codable, Sendable, Equatable {
    case caption, body, title, display
}

public enum WidgetFontWeight: String, Codable, Sendable, Equatable {
    case light, regular, medium, bold
}

public enum WidgetAlignment: String, Codable, Sendable, Equatable {
    case leading, center, trailing
}

public enum WidgetActionType: String, Codable, Sendable, Equatable {
    case openURL, copy, refresh
}

public struct WidgetAction: Codable, Sendable, Equatable {
    public let type: WidgetActionType
    public let value: String?
}

public struct WidgetComponent: Codable, Sendable, Equatable {
    public let type: WidgetComponentType
    public let children: [WidgetComponent]?
    /// list: template rendered per element.
    public let item: Box<WidgetComponent>?
    public let each: String?
    /// list: loop variable name (JSON key: "as").
    public let loopVariable: String?
    public let limit: Int?
    public let when: String?
    public let text: String?
    public let value: JSONValue?
    public let format: String?
    public let size: WidgetTextSize?
    public let weight: WidgetFontWeight?
    public let color: String?
    public let background: String?
    public let align: WidgetAlignment?
    public let spacing: Double?
    public let padding: Double?
    public let radius: Double?
    public let lines: Int?
    public let kind: String?
    public let series: String?
    public let min: Double?
    public let max: Double?
    public let symbol: String?
    public let url: String?
    public let action: WidgetAction?
    /// Fixed width and height in points, for badges, bars and tiles.
    public let width: Double?
    public let height: Double?
    /// Type design: "default", "rounded", "serif" or "monospaced".
    public let design: String?

    enum CodingKeys: String, CodingKey {
        case type, children, item, each, limit, when, text, value, format
        case size, weight, color, background, align, spacing, padding, radius
        case lines, kind, series, min, max, symbol, url, action, width, height, design
        case loopVariable = "as"
    }
}
