//
//  CustomTabBar.swift
//  RWF FEED
//
//  A hand-rolled bottom bar instead of SwiftUI's TabView. With 6 tabs, the system tab bar
//  (backed by UITabBarController) collapses everything past the 4th item into a "More" list —
//  there's no supported way to opt out of that once you cross 5 tabs. Rolling our own bar
//  keeps all 6 directly reachable in one tap.
//

import SwiftUI
import TipKit

struct CustomTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Theme.divider)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            .background(Theme.cardSurface)
        }
    }

    @ViewBuilder
    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selection == tab
        let button = Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.rwf(size: 19))
                Text(tab.title)
                    .font(.rwf(size: 9.5, weight: .medium))
            }
            .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])

        // TipKit onboarding — only the two tabs whose meaning isn't obvious from name/icon
        // alone get a first-visit tip; everything else (Feed, Tracker, Bosses, News) is
        // self-explanatory and left untouched.
        switch tab {
        case .heartbreak:
            button.popoverTip(HeartbreakTabTip(), arrowEdge: .bottom)
        case .kills:
            button.popoverTip(KillsTabTip(), arrowEdge: .bottom)
        default:
            button
        }
    }
}
