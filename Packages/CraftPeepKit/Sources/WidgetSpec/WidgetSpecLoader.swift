import Foundation

// MARK: - Errors

public enum WidgetSpecError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The data is not valid JSON, or does not match the spec's structure.
    case malformed(String)
    /// The file declares a spec version this runtime does not support.
    case unsupportedSpecVersion(found: String, supported: String)
    /// The file decoded but breaks one or more spec rules.
    case invalid([String])

    public var description: String {
        switch self {
        case .malformed(let message):
            return "Malformed widget file: \(message)"
        case .unsupportedSpecVersion(let found, let supported):
            return "Unsupported spec version \(found) (this app supports \(supported)). Update the app."
        case .invalid(let issues):
            return "Invalid widget:\n" + issues.map { "- \($0)" }.joined(separator: "\n")
        }
    }
}

// MARK: - Loader

public enum WidgetSpecLoader {
    /// Decodes and validates a widget file.
    public static func decode(_ data: Data) throws -> WidgetDefinition {
        struct Header: Decodable {
            let spec: String?
        }

        let decoder = JSONDecoder()

        let header: Header
        do {
            header = try decoder.decode(Header.self, from: data)
        } catch {
            throw WidgetSpecError.malformed(describe(error))
        }

        guard let found = header.spec else {
            throw WidgetSpecError.invalid(["Missing required field 'spec'"])
        }
        guard WidgetSpecInfo.supportedVersions.contains(found) else {
            throw WidgetSpecError.unsupportedSpecVersion(
                found: found,
                supported: WidgetSpecInfo.version
            )
        }

        let definition: WidgetDefinition
        do {
            definition = try decoder.decode(WidgetDefinition.self, from: data)
        } catch {
            throw WidgetSpecError.malformed(describe(error))
        }

        let issues = definition.validate()
        guard issues.isEmpty else {
            throw WidgetSpecError.invalid(issues)
        }
        return definition
    }

    /// Reads, decodes and validates a widget file from disk.
    public static func load(from url: URL) throws -> WidgetDefinition {
        try decode(Data(contentsOf: url))
    }

    private static func describe(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return String(describing: error)
        }
        func path(_ context: DecodingError.Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "(root)" : joined
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case .typeMismatch(_, let context),
             .valueNotFound(_, let context),
             .dataCorrupted(let context):
            return "\(context.debugDescription) at \(path(context))"
        @unknown default:
            return String(describing: decodingError)
        }
    }
}

// MARK: - Query vocabulary

/// The closed sets a `query` source may use. Kept as strings so this module depends on nothing;
/// a test in the runtime checks they match the app's own types.
public enum WidgetQueryVocabulary {
    public static let collections: Set<String> = ["stories", "repositories"]
    /// The fixed views; "folder:<name>" is also allowed.
    public static let views: Set<String> = ["overview", "ai", "latest", "saved"]
    public static let designs: Set<String> = ["default", "rounded", "serif", "monospaced"]

    public static func isKnownView(_ view: String) -> Bool {
        views.contains(view) || (view.hasPrefix("folder:") && view.count > "folder:".count)
    }
    public static let sorts: Set<String> = ["rank", "latest"]
    public static let subjects: Set<String> = ["all", "ai"]
    public static let kinds: Set<String> = [
        "shipping", "announcement", "research", "benchmark", "funding", "partnership", "speculation", "unverified_claim"
    ]
}

// MARK: - Validation

extension WidgetDefinition {
    /// Checks rules the JSON structure alone cannot express. Returns human-readable issues.
    public func validate() -> [String] {
        var issues: [String] = []

        if id.range(of: #"^[a-z0-9]+(\.[a-z0-9-]+)+$"#, options: .regularExpression) == nil {
            issues.append("id '\(id)' must be reverse-DNS style, for example com.example.clock")
        }
        if version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) == nil {
            issues.append("version '\(version)' must look like 1.0.0")
        }
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("name must not be empty")
        }
        if let symbol, symbol.range(of: #"^[a-z0-9.]{1,60}$"#, options: .regularExpression) == nil {
            issues.append("symbol '\(symbol)' must be an SF Symbol name such as newspaper.fill")
        }

        // View
        let allowedViewKeys: Set<String> = ["default", "small", "medium", "large"]
        if view["default"] == nil {
            issues.append("view must contain a 'default' entry")
        }
        for key in view.keys.sorted() where !allowedViewKeys.contains(key) {
            issues.append("view key '\(key)' must be one of default, small, medium, large")
        }
        for (key, component) in view.sorted(by: { $0.key < $1.key }) {
            collectComponentIssues(component, path: "view.\(key)", into: &issues)
        }

        // Settings
        var seenKeys = Set<String>()
        for setting in settings ?? [] {
            if !seenKeys.insert(setting.key).inserted {
                issues.append("duplicate setting key '\(setting.key)'")
            }
            if setting.type == .select, (setting.options ?? []).isEmpty {
                issues.append("setting '\(setting.key)' is a select but has no options")
            }
        }

        // Capabilities that existed on paper in 0.1 and are refused outright: a widget is data, and
        // can never run commands or read files.
        if permissions?.commands != nil {
            issues.append("permissions.commands is not supported: widgets cannot run commands")
        }
        if permissions?.files != nil {
            issues.append("permissions.files is not supported: widgets cannot read files")
        }

        // Data sources
        let allowedHosts = Set((permissions?.network ?? []).map { $0.lowercased() })
        let allowedSystem = Set(permissions?.system ?? [])

        for (name, source) in (data ?? [:]).sorted(by: { $0.key < $1.key }) {
            let label = "data.\(name)"
            switch source.type {
            case .http, .rss:
                guard let url = source.url else {
                    issues.append("\(label): \(source.type.rawValue) source needs a 'url'")
                    break
                }
                if !url.hasPrefix("https://") {
                    issues.append("\(label): url must start with https://")
                } else if let host = Self.literalHost(of: url) {
                    if !allowedHosts.contains(host) {
                        issues.append("\(label): host '\(host)' is not listed in permissions.network")
                    }
                } else {
                    issues.append("\(label): url host must be written out, not built from an expression")
                }
                if source.each != nil, source.loopVariable == nil {
                    issues.append("\(label): 'each' needs a matching 'as'")
                }
            case .ai:
                if permissions?.ai != true {
                    issues.append("\(label): ai source needs permissions.ai = true")
                }
                if source.prompt == nil {
                    issues.append("\(label): ai source needs a 'prompt'")
                }
            case .system:
                if let kind = source.kind {
                    if !allowedSystem.contains(kind) {
                        issues.append("\(label): system kind '\(kind)' is not listed in permissions.system")
                    }
                } else {
                    issues.append("\(label): system source needs a 'kind'")
                }
            case .query:
                if spec == "0.1" {
                    issues.append("\(label): query sources need spec 0.2")
                }
                if !WidgetQueryVocabulary.collections.contains(source.from ?? "") {
                    issues.append("\(label): query 'from' must be one of \(WidgetQueryVocabulary.collections.sorted().joined(separator: ", "))")
                }
                if source.from == "repositories", source.sort == "latest" {
                    issues.append("\(label): repositories can only be sorted by rank")
                }
                if let sort = source.sort, !WidgetQueryVocabulary.sorts.contains(sort) {
                    issues.append("\(label): sort must be one of \(WidgetQueryVocabulary.sorts.sorted().joined(separator: ", "))")
                }
                if let limit = source.limit, !(1...50).contains(limit) {
                    issues.append("\(label): limit must be between 1 and 50")
                }
                if let hours = source.filter?.sinceHours, !(hours >= 1 && hours <= 2160) {
                    issues.append("\(label): sinceHours must be between 1 and 2160")
                }
                for kind in source.filter?.kinds ?? [] where !WidgetQueryVocabulary.kinds.contains(kind) {
                    issues.append("\(label): unknown kind '\(kind)'")
                }
                // A subject written out must be a known one; one built from a setting is checked when it runs.
                if let subject = source.filter?.subject, !subject.contains("{{"), !WidgetQueryVocabulary.subjects.contains(subject) {
                    issues.append("\(label): unknown subject '\(subject)'")
                }
                if let view = source.filter?.view, !view.contains("{{"), !WidgetQueryVocabulary.isKnownView(view) {
                    issues.append("\(label): unknown view '\(view)'")
                }
                if (source.filter?.entities?.count ?? 0) > 20 {
                    issues.append("\(label): at most 20 entities")
                }
            case .static, .time:
                break
            }
        }

        return issues
    }

    private func collectComponentIssues(
        _ component: WidgetComponent,
        path: String,
        into issues: inout [String]
    ) {
        for (key, value) in [("width", component.width), ("height", component.height)] {
            if let value, !(0...600).contains(value) {
                issues.append("\(path): \(key) must be between 0 and 600")
            }
        }
        if let design = component.design, !WidgetQueryVocabulary.designs.contains(design) {
            issues.append("\(path): design must be one of default, rounded, serif, monospaced")
        }
        if component.type == .list {
            if component.each == nil {
                issues.append("\(path): list needs 'each'")
            }
            if component.item == nil {
                issues.append("\(path): list needs 'item'")
            }
        }
        for (index, child) in (component.children ?? []).enumerated() {
            collectComponentIssues(child, path: "\(path).children[\(index)]", into: &issues)
        }
        if let item = component.item {
            collectComponentIssues(item.value, path: "\(path).item", into: &issues)
        }
    }

    /// Host of an https URL, or nil when the host is empty or contains an expression.
    private static func literalHost(of url: String) -> String? {
        let rest = url.dropFirst("https://".count)
        let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == ":" })
            ?? rest.endIndex
        let host = String(rest[..<end])
        if host.isEmpty || host.contains("{{") {
            return nil
        }
        return host.lowercased()
    }
}
