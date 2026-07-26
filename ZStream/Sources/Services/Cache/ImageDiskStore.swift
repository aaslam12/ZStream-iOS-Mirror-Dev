//
//  ImageDiskStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import UIKit

actor ImageDiskStore {
    static let shared = ImageDiskStore()

    private let fileManager = FileManager.default
    private let directory: URL

    init(directoryName: String = "ZStreamImageCache") {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(directoryName)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func read(key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func write(_ data: Data, key: String) {
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    func currentUsageBytes() -> Int64 {
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(Int64(0)) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func enforceLimit(_ limitBytes: Int64) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else { return }

        let entries = files.compactMap { url -> (url: URL, size: Int64, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let date = values.contentModificationDate else { return nil }
            return (url, Int64(size), date)
        }

        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limitBytes else { return }

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard total > limitBytes else { break }
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    func clearAll() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent(key)
    }
}
