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

/// Lock to Duo's native holding orientation on both displays. UIKit maps this
/// orientation to each display's native rotation; a wider interior canvas is
/// not a reason to request a landscape rotation when the hinge changes.
final class DexAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        .portrait
    }
}

struct HingeObserver: UIViewRepresentable {
    var onUpdate: (Bool?) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        if #available(iOS 27.1, *) {
            view.addInteraction(UIHingeInteraction { _, update in
                let isOpen: Bool?
                switch update.hinge?.status {
                case .closed: isOpen = false
                case .partiallyOpen, .fullyOpen: isOpen = true
                default: isOpen = nil
                }
                Task { @MainActor in
                    onUpdate(isOpen)
                }
            })
        }
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
