//
//  NotificationSettingsView.swift
//  RWF FEED
//
//  Lets the user pick between "every feed post" and "only this guild's kills" for push
//  notifications. See NotificationPreferences for how the choice is persisted and sent to
//  the push-service Worker.
//

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject private var preferences = NotificationPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var guilds: [RaceGuild] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        preferences.setFavoriteGuild(id: nil, name: nil)
                    } label: {
                        HStack {
                            Text("All feed posts")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if preferences.favoriteGuildID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text("The default — a push for every new post in the global coverage feed.")
                }

                Section {
                    if isLoading && guilds.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let errorMessage, guilds.isEmpty {
                        Text(errorMessage)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(guilds) { guild in
                            Button {
                                preferences.setFavoriteGuild(id: guild.id, name: guild.displayName)
                            } label: {
                                HStack(spacing: 12) {
                                    GuildAvatar(guild: guild)
                                    Text(guild.displayName)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if preferences.favoriteGuildID == guild.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Only a push when this guild's boss count goes up — nothing else from the feed.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadGuilds() }
        }
        .tint(Theme.accent)
    }

    private func loadGuilds() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // raid-rankings, not the boss-progress timeline: the timeline only lists guilds
            // that have at least one kill, which leaves out top guilds (Echo, Liquid, Method…)
            // early in the race before they've killed anything yet. raid-rankings ranks
            // every tracked guild regardless of progress, so this list is complete and
            // already ordered by current standing.
            guilds = try await RaiderIOService.shared.fetchRaidRankings().map(\.guild)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load guilds."
        }
    }
}

#Preview {
    NotificationSettingsView()
}
