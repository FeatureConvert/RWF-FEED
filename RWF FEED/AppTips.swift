//
//  AppTips.swift
//  RWF FEED
//
//  TipKit copy for first-visit onboarding — two tab tips (Heartbreak, Kills) anchored in
//  CustomTabBar, plus the Close Call Threshold slider tip in Settings. TipKit itself handles
//  "seen it, don't show again" persistence and Reduce Motion; Tips.configure() is called once
//  from RWF_FEEDApp.init().
//

import SwiftUI
import TipKit

struct HeartbreakTabTip: Tip {
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

struct KillsTabTip: Tip {
    var title: Text {
        Text("Kills")
    }
    var message: Text? {
        Text("Every confirmed boss kill across all guilds, ranked by who killed it first.")
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
