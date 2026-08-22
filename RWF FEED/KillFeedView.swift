//
//  KillFeedView.swift
//  RWF FEED
//
//  A chronological log of every boss kill across every guild — not just the narrative
//  blog posts in the main feed, and not just the current per-guild standing in Tracker.
//

import SwiftUI

struct KillFeedView: View {
    @StateObject private var viewModel = KillFeedViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Venomous Abyss", isLoading: viewModel.isLoading)

                Group {
                    if viewModel.events.isEmpty && viewModel.isLoading {
                        ProgressView("Loading kill feed…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.events.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else {
                        List(Array(viewModel.events.enumerated()), id: \.element.id) { index, event in
                            KillFeedRow(event: event, isLast: index == viewModel.events.count - 1)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    }
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(Theme.accent)
        .task {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

struct KillFeedRow: View {
    let event: KillFeedEvent
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                GuildAvatar(guild: event.guild)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(event.guild.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("killed")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 6) {
                        AsyncImage(url: event.boss.fullIconURL) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                        Text(event.boss.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    if event.rank == 1 {
                        Text("WORLD FIRST")
                            .font(Theme.liveBadgeLabel)
                            .tracking(Theme.liveBadgeTracking)
                            .foregroundStyle(Color(hex: "#292B31"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#D2CEFD"), in: Capsule())
                    } else {
                        Text(event.rankLabel)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(RelativeTime.short(from: event.defeatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, Theme.trackerRowVPadding)
            .padding(.horizontal, Theme.trackerRowHPadding)

            if !isLast {
                FadingDivider()
            }
        }
    }
}

#Preview {
    KillFeedView()
}
