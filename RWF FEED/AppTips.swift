//
//  AppTips.swift
//  RWF FEED
//
//  TipKit copy for first-visit onboarding — the Close Call Threshold slider tip in Settings.
//  TipKit itself handles "seen it, don't show again" persistence and Reduce Motion;
//  Tips.configure() is called once from RWF_FEEDApp.init().
//

import SwiftUI
import TipKit

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
