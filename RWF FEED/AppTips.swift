//
//  AppTips.swift
//  RWF FEED
//
//  TipKit copy for first-visit onboarding — the Heartbreak screen tip, the Boss List kill-
//  disclosure tip (anchored to each screen's own header now that CustomTabBar and its
//  popoverTip-on-tab-button wiring are gone), and the Close Call Threshold slider tip in
//  Settings. TipKit itself handles "seen it, don't show again" persistence and Reduce Motion;
//  Tips.configure() is called once from RWF_FEEDApp.init().
//

import SwiftUI
import TipKit

struct HeartbreakScreenTip: Tip {
    var title: Text {
        Text("Heartbreak")
    }
    var message: Text? {
        Text("Close calls — guilds that just missed a kill, ranked by how little boss health was left.")
    }
    var image: Image? {
        Image(systemName: "heart.slash.fill")
    }
}

struct KillsDisclosureTip: Tip {
    var title: Text {
        Text("See Every Kill")
    }
    var message: Text? {
        Text("Tap a boss to see its top 3 kills — World First plus the runners-up.")
    }
    var image: Image? {
        Image(systemName: "checkmark.seal.fill")
    }
}

struct CloseCallThresholdTip: Tip {
    var title: Text {
        Text("Close Call Threshold")
    }
    var message: Text? {
        Text("How much boss health has to remain on a failed pull for it to count as a close call.")
    }
    var image: Image? {
        Image(systemName: "percent")
    }
}
