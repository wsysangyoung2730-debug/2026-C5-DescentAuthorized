import GameKit
import SwiftUI
import UIKit

struct GameCenterAuthenticationView: UIViewControllerRepresentable {
    let viewController: UIViewController

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .black
        container.addChild(viewController)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        container.view.addSubview(viewController.view)
        NSLayoutConstraint.activate([
            viewController.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            viewController.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            viewController.view.bottomAnchor.constraint(equalTo: container.view.bottomAnchor)
        ])
        viewController.didMove(toParent: container)
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(
        _ uiViewController: UIViewController,
        coordinator: Void
    ) {
        guard let child = uiViewController.children.first else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
    }
}

struct GameCenterDashboardView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: dismiss.callAsFunction)
    }

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let viewController = GKGameCenterViewController(state: .achievements)
        viewController.gameCenterDelegate = context.coordinator
        return viewController
    }

    func updateUIViewController(
        _ uiViewController: GKGameCenterViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        private let onDismiss: () -> Void

        init(onDismiss: @escaping () -> Void) {
            self.onDismiss = onDismiss
        }

        func gameCenterViewControllerDidFinish(
            _ gameCenterViewController: GKGameCenterViewController
        ) {
            onDismiss()
        }
    }
}
