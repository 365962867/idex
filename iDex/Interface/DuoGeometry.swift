import SwiftUI
import UIKit

/// The scanner uses one panel-local coordinate system in both postures.
/// Unfolding adds space at the leading edge; it never centers the scanner over the full display.
struct DuoGeometry {
    let size: CGSize
    var hingeIsOpen: Bool? = nil
    var isOpen: Bool { size.width >= 850 && size.height >= 600 && hingeIsOpen != false }
    var panelWidth: CGFloat { min(size.width, 466) }
    var rightOrigin: CGFloat { size.width - panelWidth }
    var viewfinder: CGRect {
        let side = max(100, min(panelWidth - 96, 320))
        return CGRect(x: rightOrigin + (panelWidth - side) / 2, y: 179, width: side, height: side)
    }
}

/// Duo's cover and interior have different natural orientations. Keep the
/// cover upright and the unfolded device in its book-like landscape posture.
@MainActor final class DuoPosture {
    static let shared = DuoPosture()
    private(set) var orientationMask: UIInterfaceOrientationMask = .portrait
    private var lastIsOpen: Bool?

    func update(isOpen: Bool, scene: UIWindowScene?) {
        let mask: UIInterfaceOrientationMask = isOpen ? .landscapeRight : .portrait
        guard lastIsOpen != isOpen || scene?.effectiveGeometry.interfaceOrientation.isLandscape != isOpen else { return }
        lastIsOpen = isOpen
        orientationMask = mask
        scene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            // Geometry can be temporarily unavailable during a system presentation.
            // The layout remains bounded and retries on the next hinge update.
            _ = error
        }
    }
}

final class DexAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        DuoPosture.shared.orientationMask
    }
}

struct HingeObserver: UIViewRepresentable {
    var onUpdate: (Bool?) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { [weak view] _, update in
                let isOpen: Bool?
                switch update.hinge?.status {
                case .closed: isOpen = false
                case .partiallyOpen, .fullyOpen: isOpen = true
                default: isOpen = nil
                }
                Task { @MainActor in
                    if let isOpen { DuoPosture.shared.update(isOpen: isOpen, scene: view?.window?.windowScene) }
                    onUpdate(isOpen)
                }
            })
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
