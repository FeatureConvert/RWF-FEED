//
//  SettingsView.swift
//  RWF FEED
//
//  Appearance mode, a bug/feature feedback shortcut, and a random WoW fact — opened from the
//  gear icon on the Feed tab.
//

import SwiftUI
import UIKit
import MessageUI
import StoreKit

private enum AppIconOption: String, CaseIterable, Identifiable {
    case `default`, horde, alliance

    var id: String { rawValue }

    /// nil means the primary icon — UIApplication's own convention for "no alternate set".
    var iconName: String? {
        switch self {
        case .default: return nil
        case .horde: return "AppIcon-Horde"
        case .alliance: return "AppIcon-Alliance"
        }
    }

    var label: String {
        switch self {
        case .default: return "Default"
        case .horde: return "Horde"
        case .alliance: return "Alliance"
        }
    }

    static var current: AppIconOption {
        switch UIApplication.shared.alternateIconName {
        case AppIconOption.horde.iconName: return .horde
        case AppIconOption.alliance.iconName: return .alliance
        default: return .default
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ObservedObject private var appearance = AppearanceSettings.shared
    @ObservedObject private var notificationPreferences = NotificationPreferences.shared
    @ObservedObject private var defaultTabSettings = DefaultTabSettings.shared
    @ObservedObject private var supporterStore = SupporterStore.shared
    @State private var showingMailCompose = false
    @State private var selectedIconOption = AppIconOption.current
    /// The slider's live value while dragging. Bound separately from
    /// notificationPreferences.heartbreakThresholdPercent, whose didSet fires a network POST —
    /// binding the slider straight to that would fire one POST per drag tick, and since
    /// arrival order isn't guaranteed, the last request to *land* (not the value released)
    /// wins server-side. Only committed to the real preference (and thus sent) on drag end.
    @State private var draftThreshold: Double = NotificationPreferences.shared.heartbreakThresholdPercent
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
                    Picker("Default Tab", selection: $defaultTabSettings.defaultTab) {
                        ForEach(AppTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.icon).tag(tab)
                        }
                    }
                } header: {
                    Text("Startup")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    Text("Which tab opens when you launch the app.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.cardSurface)

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
                    Text("Raider.IO Updates covers new feed posts, Major Heartbreaker close-call alerts, and World First kill announcements. Spoiler-Free Mode hides which guild/boss in World First pushes — you'll still be alerted, just as \"Spoiler Alert\" instead.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.cardSurface)

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Close Call Threshold")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "%.1f%%", draftThreshold))
                                .foregroundStyle(Theme.textSecondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $draftThreshold, in: 1...25, step: 0.5,
                            onEditingChanged: { isEditing in
                                if !isEditing {
                                    notificationPreferences.heartbreakThresholdPercent = draftThreshold
                                }
                            }
                        )
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, 2)

                    Toggle(isOn: $notificationPreferences.notifyNonWorldFirstHeartbreaks) {
                        Label("Notify for Non-World-First Close Calls", systemImage: "flag.checkered")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                } header: {
                    Text("Close Calls")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    Text("Major Heartbreaker pushes when a guild's best pull drops under this remaining health%, on a new record low. By default that only covers bosses still part of the World First race — turn the toggle on to also get pushed for a guild's close call on a boss another guild has already killed.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.cardSurface)

                Section {
                    if supporterStore.isSupporter {
                        Label("You're a Supporter — thank you!", systemImage: "star.fill")
                            .foregroundStyle(Theme.textPrimary)

                        Picker("App Icon", selection: $selectedIconOption) {
                            ForEach(AppIconOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .onChange(of: selectedIconOption) { _, newValue in
                            setIcon(newValue)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Remove ads and unlock alternate app icons with a one-time purchase.")
                                .foregroundStyle(Theme.textPrimary)
                            if let product = supporterStore.product {
                                Button {
                                    Task { await supporterStore.purchase() }
                                } label: {
                                    HStack {
                                        Text("Become a Supporter")
                                        Spacer()
                                        Text(product.displayPrice)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .disabled(supporterStore.isLoading)
                            } else if supporterStore.hasAttemptedProductLoad {
                                Text("Not available right now — check your connection and try again later.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .padding(.vertical, 2)

                        Button("Restore Purchases") {
                            Task { await supporterStore.restorePurchases() }
                        }
                        .disabled(supporterStore.isLoading)
                    }

                    if let error = supporterStore.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Supporter")
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

                    Text("Azeroth Watch is a fan-made, unofficial app and is not affiliated with, endorsed by, or sponsored by Blizzard Entertainment, Inc., Raider.IO, or Wowhead/ZAM Network, LLC. World of Warcraft and Blizzard Entertainment are trademarks of Blizzard Entertainment, Inc. Raider.IO and Wowhead are trademarks of their respective owners.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
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

    private func setIcon(_ option: AppIconOption) {
        Task {
            try? await UIApplication.shared.setAlternateIconName(option.iconName)
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
