import Domain
import Foundation

/// The default sources shipped with the app. Each entry's feed URL and tier are checked by hand;
/// see Docs/DATA_SOURCES.md for when.
public enum SourceCatalogue {
    public static func bundled() throws -> [SourceDefinition] {
        guard let url = Bundle.module.url(forResource: "sources.catalog", withExtension: "json") else {
            throw IngestionError.malformed("bundled source catalogue is missing")
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> [SourceDefinition] {
        try JSONDecoder().decode(File.self, from: data).sources
    }

    private struct File: Decodable {
        let sources: [SourceDefinition]
    }
}
