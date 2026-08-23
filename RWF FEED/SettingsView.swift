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
    @ObservedObject private var notificationPreferences = NotificationPreferences.shared
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
                    Toggle(isOn: $notificationPreferences.raiderioEnabled) {
                        Label("Raider.IO Updates", systemImage: "bolt.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $notificationPreferences.wowheadEnabled) {
                        Label("Wowhead News", systemImage: "newspaper.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    Toggle(isOn: $notificationPreferences.spoilerFreeEnabled) {
                        Label("Spoiler-Free Mode", systemImage: "eye.slash.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Notifications")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    Text("Raider.IO Updates covers new feed posts and Major Heartbreaker close-call alerts. Spoiler-Free Mode hides which guild/boss in World First kill notifications — you'll still be alerted, just as \"Spoiler Alert\" instead.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.cardSurface)

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

                    Link(destination: URL(string: "https://www.wowhead.com/news")!) {
                        HStack(spacing: 5) {
                            Image("WowheadMark")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                            Text("News provided by Wowhead")
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
