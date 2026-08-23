//
//  SettingsView.swift
//  RWF FEED
//
//  Appearance mode, a bug/feature feedback shortcut, and a random WoW fact — opened from the
//  gear icon on the Feed tab.
//

import SwiftUI
import MessageUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var appearance = AppearanceSettings.shared
    @State private var showingMailCompose = false
    private let funFact = WoWFunFacts.random()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appearance.mode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 4)
                } header: {
                    Text("Appearance")
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    Button(action: sendFeedback) {
                        Label("Report a Bug / Feature Request", systemImage: "envelope")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.cardSurface)
                }

                Section {
                    Text(funFact)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .listRowBackground(Theme.cardSurface)
                } header: {
                    Text("Did You Know?")
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    Link(destination: URL(string: "https://raider.io")!) {
                        HStack(spacing: 5) {
                            Image("RaiderIOMark")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text("Data provided by Raider.IO")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)

                    Text("Created by Nxh - Illidan US 2026")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showingMailCompose) {
            MailComposeView()
        }
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            showingMailCompose = true
        } else if let url = FeedbackMail.mailtoURL {
            openURL(url)
        }
    }
}

#Preview {
    SettingsView()
}
