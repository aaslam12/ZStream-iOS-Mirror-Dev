//
//  ImageCacheManager.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import UIKit

@MainActor
final class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()

    enum CacheLevel: String, CaseIterable, Identifiable {
        case low, medium, high, extra
        var id: String { rawValue }
        var label: String {
            switch self {
            case .low: return "Low"
            case .medium: return "Medium"
            case .high: return "High"
            case .extra: return "Extra"
            }
        }
        
        var memoryLimitBytes: Int {
            switch self {
            case .low: return 50 * 1024 * 1024
            case .medium: return 150 * 1024 * 1024
            case .high: return 350 * 1024 * 1024
            case .extra: return 700 * 1024 * 1024
            }
        }
        
        var diskLimitBytes: Int64 {
            switch self {
            case .low: return 100 * 1024 * 1024
            case .medium: return 300 * 1024 * 1024
            case .high: return 800 * 1024 * 1024
            case .extra: return 2 * 1024 * 1024 * 1024
            }
        }
    }

    @Published var level: CacheLevel {
        didSet {
            UserPreferencesManager.mark(.imageCacheLevel, value: level.rawValue)
            memoryCache.totalCostLimit = level.memoryLimitBytes
        }
    }

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskStore = ImageDiskStore.shared

    private init() {
        let saved: String? = UserPreferencesManager.value(for: .imageCacheLevel)
        level = saved.flatMap(CacheLevel.init(rawValue:)) ?? .medium
        memoryCache.totalCostLimit = level.memoryLimitBytes
    }

    /// Synchronous, memory-only check — instant, safe to call from a View's body.
    func memoryCachedImage(for url: URL) -> UIImage? {
        memoryCache.object(forKey: cacheKey(for: url) as NSString)
    }

    /// Full check including disk — async since disk I/O happens off the main actor.
    func cachedImage(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)
        if let hit = memoryCache.object(forKey: key as NSString) {
            return hit
        }
        guard let data = await diskStore.read(key: key), let image = UIImage(data: data) else {
            return nil
        }
        memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
        return image
    }

    func store(_ image: UIImage, data: Data, for url: URL) async {
        let key = cacheKey(for: url)
        memoryCache.setObject(image, forKey: key as NSString, cost: data.count)
        await diskStore.write(data, key: key)
        await diskStore.enforceLimit(level.diskLimitBytes)
    }

    func clearAll() {
        memoryCache.removeAllObjects()
        Task { await diskStore.clearAll() }
    }

    func currentDiskUsageBytes() async -> Int64 {
        await diskStore.currentUsageBytes()
    }

    private func cacheKey(for url: URL) -> String {
        String(url.absoluteString.hashValue)
    }
}
