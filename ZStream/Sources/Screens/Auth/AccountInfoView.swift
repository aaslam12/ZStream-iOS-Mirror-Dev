//
//  AccountInfoView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/17/26.
//

import SwiftUI

struct AccountInfoView: View {
    @Binding var profile: AccountProfile
    let onNext: () -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Color(hex: profile.colorOneHex)).frame(width: 84, height: 84)
                    Image(systemName: profile.iconName).font(.system(size: 32)).foregroundStyle(.white)
                }

                Text("Account information").font(.title2.bold())
                Text("Enter a name for your device then pick colors and a user icon of your choosing!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Device name").bold()
                    TextField("Personal phone", text: $profile.deviceName)
                        .padding()
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }

                colorPicker(title: "Profile color one", selection: $profile.colorOneHex)
                colorPicker(title: "Profile color two", selection: $profile.colorTwoHex)

                VStack(alignment: .leading, spacing: 8) {
                    Text("User icon").bold().frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(ProfileIconOption.icons, id: \.self) { icon in
                            Button {
                                profile.iconName = icon
                            } label: {
                                Image(systemName: icon)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(profile.iconName == icon ? Color.blue.opacity(0.3) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(profile.iconName == icon ? Color.blue : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                
                Button {
                    onNext()
                } label: {
                    Text("Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(profile.deviceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
        }
        .dismissKeyboardOnTap()
    }

    private func colorPicker(title: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).bold().frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(ProfileIconOption.colors, id: \.self) { hex in
                    Button {
                        selection.wrappedValue = hex
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: hex))
                            .frame(height: 44)
                            .overlay {
                                if selection.wrappedValue == hex {
                                    Image(systemName: "checkmark").foregroundStyle(.white)
                                }
                            }
                    }
                }
            }
        }
    }
}
