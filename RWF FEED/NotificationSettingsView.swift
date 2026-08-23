//
//  NotificationSettingsView.swift
//  RWF FEED
//
//  Lets the user pick between "every feed post" and "only these guilds' kills" for push
//  notifications. Favorite guilds are typed by name rather than picked from a list — each is
//  matched against the currently tracked guilds and added to the list (see
//  NotificationPreferences for how the list is persisted and sent to the push-service Worker).
//

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject private var preferences = NotificationPreferences.shared
    @Environment(\.dismiss) private var dismiss
    @State private var guilds: [RaceGuild] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var guildNameInput = ""
    @State private var matchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        preferences.clearFavorites()
                        matchError = nil
                    } label: {
                        HStack {
                            Text("All feed posts")
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if preferences.favoriteGuilds.isEmpty {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                } footer: {
                    Text("The default — a push for every new post in the global coverage feed.")
                }

                Section {
                    ForEach(preferences.favoriteGuilds) { guild in
                        Text(guild.name)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            preferences.removeFavoriteGuild(id: preferences.favoriteGuilds[index].id)
                        }
                    }

                    HStack {
                        TextField("Guild name", text: $guildNameInput)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .onSubmit(addMatchedGuild)
                        Button("Add", action: addMatchedGuild)
                            .disabled(guildNameInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if let matchError {
                        Text(matchError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    } else if let loadError {
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } header: {
                    Text("Favorite guilds")
                } footer: {
                    Text("Type a guild's name exactly as it appears on raider.io — a push whenever any of these guilds downs a new boss.")
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
            guilds = try await RaiderIOService.shared.fetchRaidRankings().map(\.guild)
            loadError = nil
        } catch {
            loadError = "Couldn't load the guild list to match against."
        }
    }

    private func addMatchedGuild() {
        let query = guildNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        if let exact = guilds.first(where: { $0.displayName.caseInsensitiveCompare(query) == .orderedSame }) {
            apply(exact)
            return
        }

        let partial = guilds.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        if partial.count == 1, let match = partial.first {
            apply(match)
        } else if partial.isEmpty {
            matchError = "No guild found matching \"\(query)\"."
        } else {
            matchError = "Multiple guilds match \"\(query)\" — be more specific."
        }
    }

    private func apply(_ guild: RaceGuild) {
        preferences.addFavoriteGuild(id: guild.id, name: guild.displayName)
        matchError = nil
        guildNameInput = ""
    }
}

#Preview {
    NotificationSettingsView()
}
