//
//  BannerAdView.swift
//  RWF FEED
//
//  A small, persistent AdMob banner shown above the tab bar on every tab. Uses Google's
//  published test ad unit ID for now — swap in the real ca-app-pub-.../... ad unit ID (and
//  the real GADApplicationIdentifier in Info-Ads.plist) once the AdMob console app/ad-unit
//  exist, before shipping this build.
//

import SwiftUI
import GoogleMobileAds

struct BannerAdView: UIViewRepresentable {
    static let testAdUnitID = "ca-app-pub-3940256099942544/2934735716"

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = Self.testAdUnitID
        banner.rootViewController = Self.currentRootViewController()
        banner.load(Self.nonPersonalizedRequest())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    /// Requests non-personalized ads only. This keeps the ad request consistent with the
    /// app's privacy policy ("never used for tracking") and means the Google Mobile Ads SDK
    /// never touches IDFA, so no App Tracking Transparency prompt is needed for this to work.
    private static func nonPersonalizedRequest() -> Request {
        let request = Request()
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    private static func currentRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

/// Fixed-height container so SwiftUI reserves layout space for the banner immediately,
/// rather than the view jumping once the ad finishes loading.
struct AdBannerBar: View {
    var body: some View {
        BannerAdView()
            .frame(width: 320, height: 50)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
    }
}
