//
//  PaginatedMediaRowStore.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import Foundation

@MainActor
final class PaginatedMediaRowStore: ObservableObject {
    @Published private(set) var items: [any MediaItem] = []
    @Published private(set) var isLoadingMore = false

    private var currentPage = 1
    private var hasMorePages = true
    private var hasSeeded = false
    private var seenKeys: Set<String> = []

    private let fetchPage: (Int, AppSettings) async throws -> [any MediaItem]

    private let maxRetainedItems = 80
    private let trimBuffer = 24
    private var lastTriggeredIndex = -1
    
    init(fetchPage: @escaping (Int, AppSettings) async throws -> [any MediaItem]) {
        self.fetchPage = fetchPage
    }
        
    /// Call once, when ContentStore's already-loaded page-1 data becomes
    /// available — seeds without a redundant network fetch.
    func seed(with initialItems: [any MediaItem]) {
        guard !hasSeeded else { return }
        hasSeeded = true
        items = initialItems
        seenKeys = Set(initialItems.map(Self.key))
    }

    private static func key(_ item: any MediaItem) -> String {
        "\(item.mediaType.rawValue)-\(item.id)"
    }

    func loadMoreIfNeeded(currentIndex: Int, settings: AppSettings, threshold: Int = 4) {
        trimIfNeeded(currentIndex: currentIndex)

        guard !isLoadingMore, hasMorePages else { return }
        guard currentIndex >= items.count - threshold else { return }
        guard currentIndex >= lastTriggeredIndex else { return }

        lastTriggeredIndex = items.count
        isLoadingMore = true

        Task {
            isLoadingMore = true
            defer { isLoadingMore = false }
            do {
                let nextPage = currentPage + 1
                let newItems = try await fetchPage(nextPage, settings)
                let deduped = newItems.filter { !seenKeys.contains(Self.key($0)) }
                for item in deduped { seenKeys.insert(Self.key(item)) }
                items.append(contentsOf: deduped)
                currentPage = nextPage
                hasMorePages = !newItems.isEmpty
            } catch {
                print("Pagination fetch failed: \(error)")
            }
        }
    }

    private func trimIfNeeded(currentIndex: Int) {
        guard items.count > maxRetainedItems else { return }
        let removable = max(0, currentIndex - trimBuffer)
        guard removable > 0 else { return }

        items.removeFirst(removable)
        seenKeys = Set(items.map(Self.key))
    }
}
