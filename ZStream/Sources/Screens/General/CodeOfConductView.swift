//
//  CodeOfConductView.swift
//  ZStream
//
//  Created by Francesco Macaluso on 7/21/26.
//

import SwiftUI

struct CodeOfConductView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Contributor Covenant Code of Conduct")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                section("Our Pledge") {
                    Text("We as members, contributors, and leaders pledge to make participation in our community a harassment-free experience for everyone, regardless of age, body size, visible or invisible disability, ethnicity, sex characteristics, gender identity and expression, level of experience, education, socio-economic status, nationality, personal appearance, race, religion, or sexual identity and orientation.")
                    Text("We pledge to act and interact in ways that contribute to an open, welcoming, diverse, inclusive, and healthy community.")
                }

                section("Our Standards") {
                    Text("Examples of behavior that contributes to a positive environment for our community include:")
                    bulletList([
                        "Demonstrating empathy and kindness toward other people",
                        "Being respectful of differing opinions, viewpoints, and experiences",
                        "Giving and gracefully accepting constructive feedback",
                        "Accepting responsibility and apologizing to those affected by our mistakes, and learning from the experience",
                        "Focusing on what is best not just for us as individuals, but for the overall community"
                    ])
                    Text("Examples of unacceptable behavior include:")
                        .padding(.top, 6)
                    bulletList([
                        "The use of sexualized language or imagery, and sexual attention or advances of any kind",
                        "Trolling, insulting or derogatory comments, and personal or political attacks",
                        "Public or private harassment",
                        "Publishing others' private information, such as a physical or email address, without their explicit permission",
                        "Other conduct which could reasonably be considered inappropriate in a professional setting"
                    ])
                }

                section("Enforcement Responsibilities") {
                    Text("Community leaders are responsible for clarifying and enforcing our standards of acceptable behavior and will take appropriate and fair corrective action in response to any behavior that they deem inappropriate, threatening, offensive, or harmful.")
                    Text("Community leaders have the right and responsibility to remove, edit, or reject comments, commits, code, wiki edits, issues, and other contributions that are not aligned to this Code of Conduct, and will communicate reasons for moderation decisions when appropriate.")
                }

                section("Scope") {
                    Text("This Code of Conduct applies within all community spaces, and also applies when an individual is officially representing the community in public spaces. Examples of representing our community include using an official e-mail address, posting via an official social media account, or acting as an appointed representative at an online or offline event.")
                }

                section("Enforcement") {
                    Text("Instances of abusive, harassing, or otherwise unacceptable behavior may be reported to the community leaders responsible for enforcement. All complaints will be reviewed and investigated promptly and fairly.")
                    Text("All community leaders are obligated to respect the privacy and security of the reporter of any incident.")
                }

                section("Enforcement Guidelines") {
                    Text("Community leaders will follow these Community Impact Guidelines in determining the consequences for any action they deem in violation of this Code of Conduct:")

                    guideline(number: "1", title: "Correction",
                        impact: "Use of inappropriate language or other behavior deemed unprofessional or unwelcome in the community.",
                        consequence: "A private, written warning from community leaders, providing clarity around the nature of the violation and an explanation of why the behavior was inappropriate. A public apology may be requested.")

                    guideline(number: "2", title: "Warning",
                        impact: "A violation through a single incident or series of actions.",
                        consequence: "A warning with consequences for continued behavior. No interaction with the people involved, including unsolicited interaction with those enforcing the Code of Conduct, for a specified period of time. Violating these terms may lead to a temporary or permanent ban.")

                    guideline(number: "3", title: "Temporary Ban",
                        impact: "A serious violation of community standards, including sustained inappropriate behavior.",
                        consequence: "A temporary ban from any sort of interaction or public communication with the community for a specified period of time. Violating these terms may lead to a permanent ban.")

                    guideline(number: "4", title: "Permanent Ban",
                        impact: "Demonstrating a pattern of violation of community standards, including sustained inappropriate behavior, harassment of an individual, or aggression toward or disparagement of classes of individuals.",
                        consequence: "A permanent ban from any sort of public interaction within the community.")
                }

                section("Attribution") {
                    Text("This Code of Conduct is adapted from the Contributor Covenant, version 2.0, available at contributor-covenant.org.")
                    Text("Community Impact Guidelines were inspired by Mozilla's code of conduct enforcement ladder.")
                }
            }
            .padding(20)
        }
        .navigationTitle("Code of Conduct")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func bulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item)
                }
            }
        }
    }

    private func guideline(number: String, title: String, impact: String, consequence: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(number). \(title)").font(.subheadline.bold()).foregroundStyle(.primary)
            Text("Community Impact: \(impact)")
            Text("Consequence: \(consequence)")
        }
        .padding(.top, 6)
    }
}
