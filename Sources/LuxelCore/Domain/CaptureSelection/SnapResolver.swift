public enum SnapResolver {
    public static func resolve(
        candidate: CaptureRect,
        windowFrames: [CaptureRect] = [],
        screenFrames: [CaptureRect] = [],
        magnetismRadius: Int = 8,
        isDisabled: Bool = false
    ) throws -> CaptureSnapResult {
        guard magnetismRadius >= 0 else {
            throw CaptureModelError.invalidDimensions
        }

        guard !isDisabled else {
            return CaptureSnapResult(rect: candidate, guides: [])
        }

        let targets = screenFrames.map { CaptureSnapTarget(kind: .screen, rect: $0) }
            + windowFrames.map { CaptureSnapTarget(kind: .window, rect: $0) }
        guard !targets.isEmpty else {
            return CaptureSnapResult(rect: candidate, guides: [])
        }

        let horizontalSnap = nearestSnap(
            axis: .vertical,
            candidateAnchors: candidate.verticalAnchors,
            targets: targets.flatMap(\.verticalAnchors),
            magnetismRadius: magnetismRadius
        )
        let verticalSnap = nearestSnap(
            axis: .horizontal,
            candidateAnchors: candidate.horizontalAnchors,
            targets: targets.flatMap(\.horizontalAnchors),
            magnetismRadius: magnetismRadius
        )
        let rect = try CaptureRect(
            x: candidate.originX + (horizontalSnap?.delta ?? 0),
            y: candidate.originY + (verticalSnap?.delta ?? 0),
            width: candidate.width,
            height: candidate.height
        )
        let guides = [horizontalSnap?.guide, verticalSnap?.guide].compactMap { $0 }

        return CaptureSnapResult(rect: rect, guides: guides)
    }

    private static func nearestSnap(
        axis: CaptureSnapGuideAxis,
        candidateAnchors: [CaptureSnapAnchorValue],
        targets: [CaptureSnapAnchorValue],
        magnetismRadius: Int
    ) -> CaptureSnap? {
        var nearest: CaptureSnap?

        for candidateAnchor in candidateAnchors {
            for target in targets {
                let delta = target.position - candidateAnchor.position
                let distance = abs(delta)
                guard distance <= magnetismRadius else {
                    continue
                }

                let snap = CaptureSnap(
                    delta: delta,
                    distance: distance,
                    guide: CaptureSnapGuide(
                        axis: axis,
                        position: target.position,
                        sourceAnchor: candidateAnchor.anchor,
                        targetAnchor: target.anchor,
                        targetKind: target.targetKind
                    )
                )
                if nearest.map({ distance < $0.distance }) ?? true {
                    nearest = snap
                }
            }
        }

        return nearest
    }
}

public struct CaptureSnapResult: Equatable, Sendable {
    public let rect: CaptureRect
    public let guides: [CaptureSnapGuide]

    public init(rect: CaptureRect, guides: [CaptureSnapGuide]) {
        self.rect = rect
        self.guides = guides
    }
}

public struct CaptureSnapGuide: Equatable, Sendable {
    public let axis: CaptureSnapGuideAxis
    public let position: Int
    public let sourceAnchor: CaptureSnapAnchor
    public let targetAnchor: CaptureSnapAnchor
    public let targetKind: CaptureSnapTargetKind

    public init(
        axis: CaptureSnapGuideAxis,
        position: Int,
        sourceAnchor: CaptureSnapAnchor,
        targetAnchor: CaptureSnapAnchor,
        targetKind: CaptureSnapTargetKind
    ) {
        self.axis = axis
        self.position = position
        self.sourceAnchor = sourceAnchor
        self.targetAnchor = targetAnchor
        self.targetKind = targetKind
    }
}

public enum CaptureSnapGuideAxis: String, Codable, Equatable, Sendable {
    case horizontal
    case vertical
}

public enum CaptureSnapAnchor: String, Codable, Equatable, Sendable {
    case leading
    case center
    case trailing
    case top
    case middle
    case bottom
}

public enum CaptureSnapTargetKind: String, Codable, Equatable, Sendable {
    case screen
    case window
}

private struct CaptureSnapTarget {
    let kind: CaptureSnapTargetKind
    let rect: CaptureRect

    var verticalAnchors: [CaptureSnapAnchorValue] {
        rect.verticalAnchors.map { $0.replacingTargetKind(kind) }
    }

    var horizontalAnchors: [CaptureSnapAnchorValue] {
        rect.horizontalAnchors.map { $0.replacingTargetKind(kind) }
    }
}

private struct CaptureSnapAnchorValue {
    let anchor: CaptureSnapAnchor
    let position: Int
    let targetKind: CaptureSnapTargetKind

    func replacingTargetKind(_ kind: CaptureSnapTargetKind) -> CaptureSnapAnchorValue {
        CaptureSnapAnchorValue(anchor: anchor, position: position, targetKind: kind)
    }
}

private struct CaptureSnap {
    let delta: Int
    let distance: Int
    let guide: CaptureSnapGuide
}

private extension CaptureRect {
    var verticalAnchors: [CaptureSnapAnchorValue] {
        [
            CaptureSnapAnchorValue(anchor: .leading, position: originX, targetKind: .screen),
            CaptureSnapAnchorValue(anchor: .trailing, position: originX + width, targetKind: .screen),
            CaptureSnapAnchorValue(anchor: .center, position: originX + width / 2, targetKind: .screen)
        ]
    }

    var horizontalAnchors: [CaptureSnapAnchorValue] {
        [
            CaptureSnapAnchorValue(anchor: .top, position: originY, targetKind: .screen),
            CaptureSnapAnchorValue(anchor: .bottom, position: originY + height, targetKind: .screen),
            CaptureSnapAnchorValue(anchor: .middle, position: originY + height / 2, targetKind: .screen)
        ]
    }
}
