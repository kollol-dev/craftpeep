/// Codable models, validation and version handling for the widget spec.
/// See Docs/SPEC.md and Schema/widget.schema.json.
public enum WidgetSpecInfo {
    /// The version new widgets are written against.
    public static let version = "0.2"
    /// Versions this runtime can load. 0.2 adds the `query` data source; nothing from 0.1 was removed
    /// except two permissions that were never implemented.
    public static let supportedVersions: Set<String> = ["0.1", "0.2"]
}
