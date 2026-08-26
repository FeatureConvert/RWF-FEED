//
//  RaceCompleteRecapView.swift
//  RWF FEED
//
//  Shown once the world's leading guild has cleared every boss — a "Final Standings" recap
//  reusing data BossBreakdownView already has in hand (standings, per-boss World First + VOD),
//  no extra raider.io calls needed.
//

import SwiftUI

struct RaceCompleteRecapView: View {
    @Environment(\.dismiss) private var dismiss
    let standings: [GuildStanding]
    let summaries: [BossSummary]

    private var winner: GuildStanding? { standings.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "trophy.fill")
                            .font(.rwf(size: 40))
                            .foregroundStyle(Theme.accent)
                        Text("Race Complete")
                            .font(.rwf(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                        if let winner {
                            Text("\(winner.guild.displayName) wins!")
                                .font(.rwf(size: 22, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(winner.map { "Race Complete. \($0.guild.displayName) wins!" } ?? "Race Complete")
                }

                Section {
                    ForEach(Array(standings.prefix(10).enumerated()), id: \.element.id) { index, standing in
                        HStack(spacing: 10) {
                            Text("\(index + 1)")
                                .font(.rwf(size: 14, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 22, alignment: .leading)
                            Text(standing.guild.displayName)
                                .font(.rwf(size: 15))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(standing.bossesDown)/\(summaries.count)")
                                .font(.rwf(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .listRowBackground(Theme.cardSurface)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Rank \(index + 1), \(standing.guild.displayName), \(standing.bossesDown) of \(summaries.count) bosses down")
                    }
                } header: {
                    Text("Final Standings")
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    ForEach(summaries) { summary in
                        HStack(spacing: 10) {
                            Group {
                                Text(summary.boss.name)
                                    .font(.rwf(size: 14))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if let worldFirst = summary.worldFirst {
                                    Text(worldFirst.guild.displayName)
                                        .font(.rwf(size: 13))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(summary.worldFirst.map { "\(summary.boss.name), World First by \($0.guild.displayName)" } ?? summary.boss.name)

                            if let worldFirst = summary.worldFirst, let vodURL = worldFirst.vodURL {
                                Link(destination: vodURL) {
                                    Image(systemName: "play.circle.fill")
                                        .foregroundStyle(Theme.accentText)
                                }
                                .accessibilityLabel("Watch the kill VOD")
                            }
                        }
                        .listRowBackground(Theme.cardSurface)
                    }
                } header: {
                    Text("Boss by Boss")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Final Standings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(Theme.accent)
    }
}
