//
//  FadeInImage.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/15/26.
//

import SwiftUI

struct FadeInImage: View {
    let url: URL?
    @State private var loadedImage: UIImage?
    @State private var isLoaded = false
    
    var body: some View {
        ZStack {
            Color.black
            
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(isLoaded ? 1 : 0)
            }
        }
        .task(id: url) {
            await load()
        }
    }
    
    private func load() async {
        guard let url else { return }
        
        if let cached = await ImageCacheManager.shared.cachedImage(for: url) {
            loadedImage = cached
            isLoaded = true
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return }
            
            await ImageCacheManager.shared.store(image, data: data, for: url)
            loadedImage = image
            withAnimation(.easeIn(duration: 0.4)) {
                isLoaded = true
            }
        } catch { }
    }
}
