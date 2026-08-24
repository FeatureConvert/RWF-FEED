//
//  HeartbreakView.swift
//  RWF FEED
//
//  Every guild's best pull on a boss they haven't killed yet, ranked closest-to-a-kill
//  first — across the whole raid, not just each boss's single frontrunner (see Boss List).
//

import SwiftUI

struct HeartbreakView: View {
    @StateObject private var viewModel = HeartbreakViewModel()
    @ObservedObject private var notificationPreferences = NotificationPreferences.shared
    @State private var showingSettings = false
    /// See FeedView's isActive doc comment — ContentView keeps every visited tab mounted, so
    /// polling has to be paused/resumed off this instead of .onDisappear (which never fires).
    var isActive: Bool = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Heartbreak", isLoading: viewModel.isLoading, lastUpdated: viewModel.lastUpdated) {
                    showingSettings = true
                }

                Group {
                    if viewModel.closeCalls.isEmpty && viewModel.isLoading {
                        ProgressView("Loading close calls…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.closeCalls.isEmpty, let message = viewModel.errorMessage {
                        ContentUnavailableView(message, systemImage: "wifi.slash")
                    } else if viewModel.closeCalls.isEmpty {
                        List {
                            ContentUnavailableView(
                                "No Close Calls Right Now",
                                systemImage: "heart.slash",
                                description: Text("Nobody's under \(String(format: "%.1f", notificationPreferences.heartbreakThresholdPercent))% on a boss they haven't killed yet.")
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .refreshable { await viewModel.refresh() }
                    } else {
                        List(Array(viewModel.closeCalls.enumerated()), id: \.element.id) { index, call in
                            CloseCallRow(
                                call: call,
                                trend: viewModel.pullTrends["\(call.guild.id)-\(call.boss.slug)"],
                                isLast: index == viewModel.closeCalls.count - 1
                            )
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
            if isActive { viewModel.startPolling() }
        }
        .onChange(of: isActive) { _, active in
            if active { viewModel.startPolling() } else { viewModel.stopPolling() }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct CloseCallRow: View {
    let call: CloseCall
    let trend: PullTrend?
    let isLast: Bool

    /// No embedded links/buttons here, unlike BossSummaryRow, so the whole row can safely
    /// collapse into one VoiceOver stop instead of guild name / boss name / percent / pull
    /// count / trend arriving as five disconnected fragments.
    private var accessibilitySummary: String {
        var parts = [
            "\(call.guild.displayName), \(call.boss.name)",
            "\(String(format: "%.2f%%", call.percent)) remaining, \(call.pullCount) pulls",
        ]
        if let trend {
            parts.append(trend.isStalled ? "holding steady" : String(format: "%+.1f%% in the last hour", trend.percentChange))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.trackerRowColumnGap) {
                GuildAvatar(guild: call.guild)

                VStack(alignment: .leading, spacing: 2) {
                    Text(call.guild.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        AsyncImage(url: call.boss.fullIconURL) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .accessibilityHidden(true)

                        Text(call.boss.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.2f%%", call.percent))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.accentText)
                        .monospacedDigit()
                    Text("\(call.pullCount) pulls")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    if let trend {
                        PullTrendLabel(trend: trend)
                    }
                }
            }
            .padding(.vertical, Theme.trackerRowVPadding)
            .padding(.horizontal, Theme.trackerRowHPadding)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)

            if !isLast {
                FadingDivider()
            }
        }
    }
}

#Preview {
    HeartbreakView()
}
