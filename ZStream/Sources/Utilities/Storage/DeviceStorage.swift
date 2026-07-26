//
//  DeviceStorage.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import Foundation

extension DownloadStorage {
    static func deviceCapacity() -> (total: Int64, free: Int64) {
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return (0, 0)
        }
        do {
            let values = try url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            let total = Int64(values.volumeTotalCapacity ?? 0)
            let free = values.volumeAvailableCapacityForImportantUsage ?? 0
            return (total, free)
        } catch {
            return (0, 0)
        }
    }
}
