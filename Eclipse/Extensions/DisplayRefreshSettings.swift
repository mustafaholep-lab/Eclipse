import SwiftUI

#if os(iOS)
import UIKit
import QuartzCore

enum DisplayRefreshSettings {
    static let storageKey = "displayRefreshRate"

    static func requestedRate(defaults: UserDefaults = .standard, maximum: Int) -> Int {
        let stored = defaults.integer(forKey: storageKey)
        return maximum >= 120 && stored != 60 ? 120 : 60
    }
}

/// A timing hint for Core Animation; iOS still controls the physical refresh rate.
private final class DisplayRefreshHintView: UIView {
    private var link: CADisplayLink?
    var active = true { didSet { updateHint() } }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        link?.invalidate()
        link = nil
        if let screen = window?.windowScene?.screen {
            link = screen.displayLink(withTarget: self, selector: #selector(frameTick))
            link?.add(to: .main, forMode: .common)
        }
        updateHint()
    }

    func updateHint() {
        guard let screen = window?.windowScene?.screen else { return }
        let fps = Float(DisplayRefreshSettings.requestedRate(maximum: screen.maximumFramesPerSecond))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        link?.isPaused = !active
    }

    func stop() { link?.invalidate(); link = nil }
    @objc private func frameTick() {}
}

private struct DisplayRefreshHint: UIViewRepresentable {
    let active: Bool
    let rate: Int

    func makeUIView(context: Context) -> DisplayRefreshHintView {
        let view = DisplayRefreshHintView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: DisplayRefreshHintView, context: Context) {
        uiView.active = active
        uiView.updateHint()
    }

    static func dismantleUIView(_ uiView: DisplayRefreshHintView, coordinator: ()) { uiView.stop() }
}

struct DisplayRefreshPresentation: ViewModifier {
    @AppStorage(DisplayRefreshSettings.storageKey, store: .standard) private var rate = 120
    @Environment(\.scenePhase) private var phase

    func body(content: Content) -> some View {
        content.background(DisplayRefreshHint(active: phase == .active, rate: rate).frame(width: 0, height: 0))
    }
}

struct DisplayRefreshSettingsView: View {
    @AppStorage(DisplayRefreshSettings.storageKey, store: .standard) private var rate = 120
    @State private var supports120 = UIScreen.main.maximumFramesPerSecond >= 120

    var body: some View {
        Form {
            Section {
                Button { rate = 60 } label: {
                    HStack { Text("60 Hz"); Spacer(); if rate == 60 || !supports120 { Image(systemName: "checkmark") } }
                }
                Button { rate = 120 } label: {
                    HStack { Text("120 Hz"); Spacer(); if rate != 60 && supports120 { Image(systemName: "checkmark") } }
                }
                .disabled(!supports120)
            } footer: {
                Text(LocalizedStringKey(supports120
                     ? "iOS may lower the refresh rate to save power or protect the device."
                     : "This display does not support 120 Hz."))
            }
        }
        .navigationTitle("Display Refresh Rate")
    }
}
#endif
