import SwiftUI
import UIKit
import Observation

final class DexSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    let store = DexStore()
    private var isTransitioningPresentation = false

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        connect(windowScene)
    }

    func connect(_ windowScene: UIWindowScene) {
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = DexHostingController(rootView: ContentView(store: store))
        self.window = window
        window.makeKeyAndVisible()
        observePresentations()
    }

    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        .portrait
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        store.resume()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        store.suspend()
    }

    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        // The scanner can be offscreen under the full-screen record when the
        // display changes, so its GeometryReader cannot own this transition.
        if DuoGeometry(size: windowScene.effectiveGeometry.coordinateSpace.bounds.size).isOpen && store.showingCompactEntry {
            store.showingCompactEntry = false
            store.showingCatalog = false
        }
    }

    // Every app presentation needs its own locking controller: the standard
    // SwiftUI sheet/cover controllers release the scene's orientation lock.
    private func observePresentations() {
        withObservationTracking {
            _ = store.showingCompactEntry
            _ = store.showingCatalog
            _ = store.showingSettings
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observePresentations()
                self?.updatePresentations()
            }
        }
    }

    private func updatePresentations() {
        guard !isTransitioningPresentation, var presenter = window?.rootViewController else { return }
        var desired: [DexPresentation] = []
        if store.showingCompactEntry { desired.append(.record) }
        if store.showingSettings { desired.append(.settings) }
        else if store.showingCatalog { desired.append(.catalog) }

        for presentation in desired {
            if let existing = presenter.presentedViewController as? DexHostingController, existing.presentation == presentation {
                presenter = existing
                continue
            }
            if presenter.presentedViewController != nil {
                dismissPresentation(from: presenter)
                return
            }

            let controller: DexHostingController
            switch presentation {
            case .record: controller = DexHostingController(rootView: CompactRecordView(store: store))
            case .catalog: controller = DexHostingController(rootView: CatalogSheet(store: store))
            case .settings: controller = DexHostingController(rootView: SettingsSheet(store: store))
            }
            controller.presentation = presentation
            controller.modalPresentationStyle = .fullScreen
            isTransitioningPresentation = true
            presenter.present(controller, animated: true) { [weak self] in
                self?.isTransitioningPresentation = false
                self?.updatePresentations()
            }
            return
        }
        if presenter.presentedViewController != nil { dismissPresentation(from: presenter) }
    }

    private func dismissPresentation(from presenter: UIViewController) {
        // PhotosPicker owns its system presentation and dismissal.
        guard presenter.presentedViewController is DexHostingController else { return }
        isTransitioningPresentation = true
        presenter.dismiss(animated: true) { [weak self] in
            self?.isTransitioningPresentation = false
            self?.updatePresentations()
        }
    }
}

enum DexPresentation {
    case record, catalog, settings
}

/// Duo's inner display ignores supported orientation masks by default. Request
/// the system's explicit orientation lock while retaining native display resizing.
final class DexHostingController: UIHostingController<AnyView> {
    var presentation: DexPresentation?

    init<Content: View>(rootView: Content) {
        super.init(rootView: AnyView(rootView))
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(rootView:)") }

    override var prefersInterfaceOrientationLocked: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }
    override var prefersStatusBarHidden: Bool { true }
    // Keep ownership of the immersive preference across SwiftUI navigation.
    override var childForHomeIndicatorAutoHidden: UIViewController? { nil }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
}
