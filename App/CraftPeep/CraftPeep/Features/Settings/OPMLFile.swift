import SwiftUI
import UniformTypeIdentifiers

/// An OPML subscription list, as a document the save and open panels can handle.
struct OPMLFile: FileDocument {
    /// Declared in CraftPeep-Info.plist, so files ending in .opml get this type once the app is registered.
    static let opml = UTType(importedAs: "org.opml.opml", conformingTo: .xml)

    /// Also the anonymous type macOS gives an .opml file when nothing has declared OPML yet, and plain XML,
    /// which some apps use for exports. The parser rejects anything that is not OPML.
    static let readableContentTypes: [UTType] = [opml, UTType(filenameExtension: "opml"), .xml].compactMap { $0 }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
