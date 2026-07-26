//
//  DownloadStorage.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

enum DownloadStorage {
    static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let downloads = base.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        excludeFromBackup(downloads)
        return downloads
    }()

    private static func excludeFromBackup(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }

    static func fileURL(named fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

}
