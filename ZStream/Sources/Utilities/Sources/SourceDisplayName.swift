//
//  SourceDisplayName.swift
//  ZStream
//
//  Turns a source id (e.g. "vidlink", "aspera") into a display name, shared
//  between SourceResolutionOverlay and the Settings preferred-source picker.
//

enum SourceDisplayName {
    static func forID(_ id: String) -> String {
        switch id.lowercased() {
        case "vidlink": return "VidLink"
        default:
            return id
                .split(whereSeparator: { $0 == "-" || $0 == "_" })
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }
}
