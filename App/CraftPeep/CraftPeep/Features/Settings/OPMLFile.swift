import SwiftUI
import UniformTypeIdentifiers

/// An OPML subscription list, as a document the save and open panels can handle.
struct OPMLFile: FileDocument {
    static let opml = UTType(filenameExtension: "opml", conformingTo: .xml) ?? .xml
    static let readableContentTypes: [UTType] = [opml, .xml]

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
