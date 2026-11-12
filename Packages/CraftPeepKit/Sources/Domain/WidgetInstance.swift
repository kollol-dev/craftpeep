import Foundation

/// A value the user chose for one of a widget's settings.
public enum WidgetSettingValue: Sendable, Equatable, Codable {
    case bool(Bool)
    case number(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}

/// One widget the user has put on the desktop: which widget, how it is set up, and where it sits.
/// The widget's definition is not stored here; it is looked up by `widgetID`.
public struct WidgetInstance: Sendable, Equatable, Identifiable {
    public var id: String
    public var widgetID: String
    public var settings: [String: WidgetSettingValue]
    /// "small", "medium" or "large".
    public var size: String
    /// Bottom-left corner in screen coordinates. Nil until the user has moved it.
    public var x: Double?
    public var y: Double?
    public var createdAt: Date

    public init(id: String, widgetID: String, settings: [String: WidgetSettingValue] = [:], size: String = "medium", x: Double? = nil, y: Double? = nil, createdAt: Date) {
        self.id = id
        self.widgetID = widgetID
        self.settings = settings
        self.size = size
        self.x = x
        self.y = y
        self.createdAt = createdAt
    }
}

public protocol WidgetInstanceRepository: Sendable {
    /// Oldest first.
    func allInstances() async throws -> [WidgetInstance]
    func save(_ instance: WidgetInstance) async throws
    func delete(instanceID: String) async throws
}
