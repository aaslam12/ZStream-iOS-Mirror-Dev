//
//  OpenSourceInfoView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import SwiftUI

struct OpenSourceInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Open-Source Status")
                    .font(.title3.bold())

                Text("The code, except for Providers, is open-source. Because it's heavily worked on without the intention to keep the code clean, we're not able to provide instructions or support for self-hosting an instance.")

                Text("For a reliable version of the open-source project to get started with hosting an instance, refer to the original repository — Celeste.")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(20)
        }
        .navigationTitle("Open Source")
        .navigationBarTitleDisplayMode(.inline)
    }
}
