//
//  DownloadsRepository.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/19/26.
//

import Foundation

struct DownloadsRepository {
    private let cache: DiskCache = .shared
    private let key = "download_records"

    func loadRecords() async -> [DownloadRecord] {
        (await cache.read([DownloadRecord].self, key: key))?.value ?? []
    }

    func add(_ record: DownloadRecord) async {
        var current = await loadRecords()
        current.removeAll { $0.id == record.id }
        current.insert(record, at: 0)
        await cache.write(current, key: key)
    }

    func remove(id: String) async {
        var current = await loadRecords()
        if let record = current.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: record.resolvedFileURL)
        }
        current.removeAll { $0.id == id }
        await cache.write(current, key: key)
    }
}
