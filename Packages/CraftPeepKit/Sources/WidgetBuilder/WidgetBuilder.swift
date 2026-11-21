import AI
import Domain
import Foundation
import WidgetSpec

/// What the builder suggests putting on the desktop. Nothing here has been installed; the user decides.
public struct WidgetProposal: Sendable, Equatable {
    public var widgetID: String
    public var size: WidgetSize
    public var settings: [String: WidgetSettingValue]
    /// One sentence, in the model's words, on what the widget will show.
    public var explanation: String
    /// Parts of the request no available widget can do, if any.
    public var unmet: String?
    /// Things the model asked for that the widget does not offer, dropped during checking.
    public var ignored: [String]

    public init(widgetID: String, size: WidgetSize, settings: [String: WidgetSettingValue], explanation: String, unmet: String? = nil, ignored: [String] = []) {
        self.widgetID = widgetID
        self.size = size
        self.settings = settings
        self.explanation = explanation
        self.unmet = unmet
        self.ignored = ignored
    }
}

public enum WidgetBuilderResult: Sendable, Equatable {
    case proposal(WidgetProposal)
    /// No available widget fits the request. The text says what is missing.
    case nothingFits(String)
}

/// Turns a description in words into a choice among the widgets the app ships and values for the settings
/// they declare. The model never writes a widget, a layout or code: it picks from a catalogue, and every
/// part of its answer is checked against that catalogue before anything is shown.
public struct WidgetBuilder: Sendable {
    static let system = """
        You help someone set up a desktop widget in the CraftPeep app.

        The user message is a JSON document with three parts. "catalogue" lists the widgets that exist; each has \
        an id, a name, a description, the sizes it comes in, and the settings it accepts with their allowed \
        values. "request" is what the person asked for, in their own words. "current", when present, is a widget \
        they already have and want changed: keep everything about it that the request does not ask to change.

        Choose the one widget from the catalogue that best does what was asked, a size it comes in, and values \
        for its settings. You can only choose from the catalogue and only use settings a widget lists. You cannot \
        invent widgets, settings, data sources or layouts.

        Return:
        - "widget_id": the id of the chosen widget, or null if nothing in the catalogue does what was asked.
        - "size": "small", "medium" or "large". Prefer "medium" unless the request implies otherwise.
        - "settings": a list of {"key", "value"} pairs, values written as text ("true", "false", a number, or \
        one of the allowed values). Only include settings you are changing from their defaults.
        - "explanation": one plain sentence saying what the widget will show.
        - "unmet": if part of the request cannot be done with what the catalogue offers, one sentence saying \
        what, otherwise null. Be direct about this; do not pretend a close match is an exact one.

        Plain text only, British English.
        """

    static let schema: JSON = object(
        [
            "widget_id": nullable("string"),
            "size": .object(["type": .string("string"), "enum": .array([.string("small"), .string("medium"), .string("large")])]),
            "settings": .object([
                "type": .string("array"),
                "items": object(["key": text, "value": text], required: ["key", "value"])
            ]),
            "explanation": text,
            "unmet": nullable("string")
        ],
        required: ["widget_id", "size", "settings", "explanation", "unmet"]
    )

    private let gateway: AIGateway

    public init(gateway: AIGateway) {
        self.gateway = gateway
    }

    /// `current` is the widget being changed, if this is an edit and not a new widget.
    public func propose(
        request: String,
        catalogue: [WidgetDefinition],
        current: WidgetInstance? = nil
    ) async throws -> WidgetBuilderResult {
        let trimmed = String(request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty else { throw ProviderError.invalidResponse("describe the widget first") }
        guard !catalogue.isEmpty else { throw ProviderError.invalidResponse("there are no widgets to choose from") }

        var correction: String?
        // One corrective round: if the model names a widget that does not exist, tell it so and ask once more.
        for attempt in 0..<2 {
            let response = try await gateway.complete(AIRequest(
                feature: .widgetBuilder, system: Self.system,
                user: Self.document(request: trimmed, catalogue: catalogue, current: current, correction: correction),
                schema: Self.schema, maxOutputTokens: 4_000, effort: .low
            ))
            guard let json = JSON.firstObject(in: response.text) else { throw ProviderError.invalidResponse("reply was not JSON") }

            switch Self.validate(json, catalogue: catalogue, current: current) {
            case .success(let result):
                return result
            case .failure(let problem):
                if attempt == 1 { throw ProviderError.invalidResponse(problem.message) }
                correction = problem.message
            }
        }
        throw ProviderError.invalidResponse("no usable answer")
    }

    // MARK: - Request document

    static func document(request: String, catalogue: [WidgetDefinition], current: WidgetInstance?, correction: String?) -> String {
        var root: [String: JSON] = [
            "request": .string(request),
            "catalogue": .array(catalogue.map(entry))
        ]
        if let current {
            root["current"] = .object([
                "widget_id": .string(current.widgetID),
                "size": .string(current.size),
                "settings": .object(current.settings.mapValues(json))
            ])
        }
        if let correction {
            root["problem_with_your_last_answer"] = .string(correction)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(JSON.object(root))) ?? Data(), as: UTF8.self)
    }

    static func entry(_ definition: WidgetDefinition) -> JSON {
        .object([
            "id": .string(definition.id),
            "name": .string(definition.name),
            "description": .string(definition.description ?? ""),
            "sizes": .array((definition.sizes ?? [.small, .medium, .large]).map { .string($0.rawValue) }),
            "settings": .array((definition.settings ?? []).filter { $0.type != .secret }.map { setting in
                var fields: [String: JSON] = [
                    "key": .string(setting.key),
                    "type": .string(setting.type.rawValue),
                    "label": .string(setting.label)
                ]
                if let help = setting.help { fields["help"] = .string(help) }
                if let options = setting.options {
                    fields["allowed_values"] = .array(options.map { .object(["value": json($0.value), "means": .string($0.label)]) })
                }
                if let defaultValue = setting.defaultValue { fields["default"] = json(defaultValue) }
                if let min = setting.min { fields["min"] = .number(min) }
                if let max = setting.max { fields["max"] = .number(max) }
                return .object(fields)
            })
        ])
    }

    // MARK: - Checking the answer

    struct Problem: Error, Equatable {
        let message: String
    }

    /// The model's answer is untrusted. Everything in it is checked against the catalogue: an unknown
    /// widget is an error; an unknown setting or a value the widget does not allow is dropped and noted.
    static func validate(_ json: JSON, catalogue: [WidgetDefinition], current: WidgetInstance?) -> Result<WidgetBuilderResult, Problem> {
        let explanation = clean(json["explanation"]?.string, limit: 300)
        let unmet = clean(json["unmet"]?.string, limit: 300)

        guard let id = json["widget_id"]?.string, !id.isEmpty else {
            return .success(.nothingFits(unmet ?? explanation ?? "None of the available widgets does that."))
        }
        guard let definition = catalogue.first(where: { $0.id == id }) else {
            let known = catalogue.map(\.id).joined(separator: ", ")
            return .failure(Problem(message: "There is no widget with id \"\(String(id.prefix(80)))\". The ids are: \(known). Use one of them or null."))
        }

        let offered = definition.sizes ?? [.small, .medium, .large]
        let asked = json["size"]?.string.flatMap(WidgetSize.init(rawValue:))
        let size = asked.flatMap { offered.contains($0) ? $0 : nil } ?? (offered.contains(.medium) ? .medium : offered.first ?? .medium)

        // An edit starts from what the user already has, so anything the model leaves out is kept.
        var settings = current?.widgetID == definition.id ? current?.settings ?? [:] : [:]
        var ignored: [String] = []
        for pair in (json["settings"]?.array ?? []).prefix(40) {
            guard let key = pair["key"]?.string, let raw = pair["value"]?.string else { continue }
            guard let setting = definition.settings?.first(where: { $0.key == key }), setting.type != .secret else {
                ignored.append("“\(String(key.prefix(40)))” is not a setting of this widget")
                continue
            }
            guard let value = value(raw, for: setting) else {
                ignored.append("“\(String(raw.prefix(40)))” is not allowed for \(setting.label)")
                continue
            }
            settings[key] = value
        }

        return .success(.proposal(WidgetProposal(
            widgetID: definition.id, size: size, settings: settings,
            explanation: explanation ?? "A \(definition.name) widget.",
            unmet: unmet, ignored: ignored
        )))
    }

    static func value(_ raw: String, for setting: WidgetSetting) -> WidgetSettingValue? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch setting.type {
        case .boolean:
            switch text.lowercased() {
            case "true", "yes", "on": return .bool(true)
            case "false", "no", "off": return .bool(false)
            default: return nil
            }
        case .number:
            guard let number = Double(text), number.isFinite else { return nil }
            return .number(min(max(number, setting.min ?? -.infinity), setting.max ?? .infinity))
        case .select:
            for option in setting.options ?? [] {
                switch option.value {
                case .string(let allowed) where allowed.lowercased() == text.lowercased(): return .string(allowed)
                case .number(let allowed) where Double(text) == allowed: return .number(allowed)
                case .bool(let allowed) where text.lowercased() == (allowed ? "true" : "false"): return .bool(allowed)
                default: continue
                }
            }
            return nil
        case .string:
            return .string(String(text.prefix(80)))
        case .color, .stringList, .secret:
            return nil
        }
    }

    // MARK: - Small helpers

    private static let text = JSON.object(["type": .string("string")])

    private static func nullable(_ type: String) -> JSON {
        .object(["anyOf": .array([.object(["type": .string(type)]), .object(["type": .string("null")])])])
    }

    private static func object(_ properties: [String: JSON], required: [String]) -> JSON {
        .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array(required.map(JSON.string)), "additionalProperties": .bool(false)
        ])
    }

    private static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }

    private static func json(_ value: JSONValue) -> JSON {
        switch value {
        case .null: .null
        case .bool(let flag): .bool(flag)
        case .number(let number): .number(number)
        case .string(let text): .string(text)
        case .array(let values): .array(values.map(json))
        case .object(let values): .object(values.mapValues(json))
        }
    }

    private static func json(_ value: WidgetSettingValue) -> JSON {
        switch value {
        case .bool(let flag): .bool(flag)
        case .number(let number): .number(number)
        case .string(let text): .string(text)
        }
    }
}
