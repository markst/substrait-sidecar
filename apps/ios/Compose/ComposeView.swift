import Shared
import SwiftUI
import UIKit

/// Hosts the shared Compose UI (the Substrait web view) from the KMP `Shared` framework.
struct ComposeView: UIViewControllerRepresentable {
    func makeUIViewController(context: Self.Context) -> UIViewController {
        let controller = MainViewControllerKt.MainViewController()
        // Reported to the page as env(safe-area-inset-top), keeping its fixed header clear of the bar.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: navigationBarHeight, left: 0, bottom: 0, right: 0)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Self.Context) {}
}
