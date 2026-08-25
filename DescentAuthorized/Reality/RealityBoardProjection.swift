import CoreGraphics

struct RealityProjectedBoard: Equatable, Sendable {
    let frame: CGRect
    let interactiveFrame: CGRect

    init(frame: CGRect, interactionInsetRatio: CGFloat = 0.045) {
        self.frame = frame.standardized
        let horizontalInset = frame.width * interactionInsetRatio
        let verticalInset = frame.height * interactionInsetRatio
        interactiveFrame = frame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    func normalizedPoint(for screenPoint: CGPoint) -> NormalizedPoint? {
        guard interactiveFrame.width > 0, interactiveFrame.height > 0,
              interactiveFrame.contains(screenPoint) else { return nil }

        return NormalizedPoint(
            x: min(max((screenPoint.x - interactiveFrame.minX) / interactiveFrame.width, 0), 1),
            y: min(max((screenPoint.y - interactiveFrame.minY) / interactiveFrame.height, 0), 1)
        )
    }

    func screenPoint(for normalizedPoint: NormalizedPoint) -> CGPoint {
        CGPoint(
            x: interactiveFrame.minX + interactiveFrame.width * normalizedPoint.x,
            y: interactiveFrame.minY + interactiveFrame.height * normalizedPoint.y
        )
    }
}

