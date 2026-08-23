//
//  WoWFunFacts.swift
//  RWF FEED
//
//  A small, deliberately conservative set of well-established WoW facts — historical/
//  well-documented enough to stay true regardless of how far past this app's release the
//  game has moved on. Shown as a "Did You Know?" line in Settings.
//

import Foundation

enum WoWFunFacts {
    static let all: [String] = [
        "World of Warcraft officially launched on November 23, 2004.",
        "The original level cap at launch was 60.",
        "Death Knights, added in Wrath of the Lich King, were WoW's first \"hero class.\"",
        "Demon Hunters, added in Legion, were WoW's second hero class.",
        "Molten Core, home to Ragnaros, was one of the very first 40-player raids in the game.",
        "Naxxramas debuted in 2006 as a 40-player raid, then was remade as a starter raid for Wrath of the Lich King in 2008.",
        "Flying mounts didn't exist until The Burning Crusade introduced them for Outland in 2007.",
        "Onyxia's Lair became famous for the server-wide message announcing the first guild to down her.",
        "The \"Leeroy Jenkins\" video — one of gaming's most iconic memes — was recorded during a Molten Core raid attempt.",
        "Blizzard doesn't run an official \"Race to World First\" — it's entirely community-organized and tracked by sites like raider.io.",
        "Pandaren became a playable race in Mists of Pandaria, alongside the Monk class.",
        "The Burning Crusade, WoW's first expansion, raised the level cap from 60 to 70.",
        "Nxh met Pakhete through WoW in 2021, later traveled halfway across the country to meet in person, and they were married in 2025.",
    ]

    static func random() -> String {
        all.randomElement() ?? all[0]
    }
}
