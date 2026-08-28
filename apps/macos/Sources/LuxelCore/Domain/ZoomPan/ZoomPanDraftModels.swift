import Foundation

public typealias ZoomExportTimeMapper = EditedTimelineMapper

extension EditedTimelineMapper {
    public func map(_ blocks: [ZoomBlock]) throws -> [ZoomBlock] {
        try blocks.flatMap { block in
            try map(block)
        }
    }

    private func map(_ block: ZoomBlock) throws -> [ZoomBlock] {
        try mapSourceRange(block.timeRange).map { range in
            try ZoomBlock(
                timeRange: range,
                targetRect: block.targetRect,
                zoom: block.zoom,
                transitionOverride: block.transitionOverride.map { $0 / speed.value }
            )
        }
    }
}

extension [ZoomBlockDraft] {
    fileprivate var activeBlocks: [ZoomBlock] {
        compactMap { draft in
            draft.state == .deleted ? nil : draft.block
        }
    }
}

public struct ZoomBlockDraftID: Codable, Equatable, Hashable, Sendable {
    public let value: String

    public init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ZoomPanModelError.invalidDraftID
        }

        self.value = value
    }
}

public enum ZoomBlockDraftOrigin: String, Codable, Equatable, Sendable {
    case manual
    case proposal
}

public enum ZoomBlockDraftState: String, Codable, Equatable, Sendable {
    case proposed
    case accepted
    case edited
    case deleted
}

public struct ZoomBlockDraft: Codable, Equatable, Sendable {
    public let id: ZoomBlockDraftID
    public let block: ZoomBlock
    public let origin: ZoomBlockDraftOrigin
    public let state: ZoomBlockDraftState

    public init(
        id: ZoomBlockDraftID,
        block: ZoomBlock,
        origin: ZoomBlockDraftOrigin,
        state: ZoomBlockDraftState
    ) throws {
        guard origin == .proposal || state != .proposed else {
            throw ZoomPanModelError.invalidDraftState
        }

        self.id = id
        self.block = block
        self.origin = origin
        self.state = state
    }

    private init(
        uncheckedID id: ZoomBlockDraftID,
        block: ZoomBlock,
        origin: ZoomBlockDraftOrigin,
        state: ZoomBlockDraftState
    ) {
        self.id = id
        self.block = block
        self.origin = origin
        self.state = state
    }

    public static func proposal(id: ZoomBlockDraftID, block: ZoomBlock) -> ZoomBlockDraft {
        ZoomBlockDraft(uncheckedID: id, block: block, origin: .proposal, state: .proposed)
    }

    public static func manual(id: ZoomBlockDraftID, block: ZoomBlock) -> ZoomBlockDraft {
        ZoomBlockDraft(uncheckedID: id, block: block, origin: .manual, state: .accepted)
    }

    public func accepting() throws -> ZoomBlockDraft {
        guard state != .deleted else {
            return self
        }

        return try ZoomBlockDraft(
            id: id,
            block: block,
            origin: origin,
            state: origin == .proposal ? .accepted : state
        )
    }

    public func replacingBlock(_ block: ZoomBlock) throws -> ZoomBlockDraft {
        guard state != .deleted else {
            return self
        }

        return try ZoomBlockDraft(
            id: id,
            block: block,
            origin: origin,
            state: .edited
        )
    }

    public func deleting() throws -> ZoomBlockDraft {
        try ZoomBlockDraft(
            id: id,
            block: block,
            origin: origin,
            state: .deleted
        )
    }
}

public struct ZoomBlockDraftCollection: Codable, Equatable, Sendable {
    public let drafts: [ZoomBlockDraft]

    public init(_ drafts: [ZoomBlockDraft]) throws {
        var ids: Set<ZoomBlockDraftID> = []
        for draft in drafts {
            guard ids.insert(draft.id).inserted else {
                throw ZoomPanModelError.duplicateDraftID
            }
        }

        try ZoomBlock.validateTimeline(drafts.activeBlocks)
        self.drafts = drafts
    }

    public var activeBlocks: [ZoomBlock] {
        drafts.activeBlocks
    }

    public func acceptingAllProposals() throws -> ZoomBlockDraftCollection {
        try ZoomBlockDraftCollection(drafts.map { try $0.accepting() })
    }

    public func replacingBlock(id: ZoomBlockDraftID, with block: ZoomBlock) throws
        -> ZoomBlockDraftCollection {
        try replacingDraft(id: id) { draft in
            try draft.replacingBlock(block)
        }
    }

    public func deleting(id: ZoomBlockDraftID) throws -> ZoomBlockDraftCollection {
        try replacingDraft(id: id) { draft in
            try draft.deleting()
        }
    }

    private func replacingDraft(
        id: ZoomBlockDraftID,
        update: (ZoomBlockDraft) throws -> ZoomBlockDraft
    ) throws -> ZoomBlockDraftCollection {
        guard let index = drafts.firstIndex(where: { $0.id == id }) else {
            throw ZoomPanModelError.unknownDraftID
        }

        var updatedDrafts = drafts
        updatedDrafts[index] = try update(updatedDrafts[index])
        return try ZoomBlockDraftCollection(updatedDrafts)
    }
}

public struct ZoomProposalTuning: Codable, Equatable, Sendable {
    public static let standard = ZoomProposalTuning(
        uncheckedClusterTimeGap: 2.5,
        minimumClusterWeight: 1.5,
        minimumBlockDuration: 1.5,
        temporalPadding: 0.25,
        targetPadding: 0.08,
        minimumZoom: 1.2,
        maximumZoom: 3,
        dwellDurationThreshold: 1.5,
        dwellMovementTolerance: 0.03,
        maxProposals: 40
    )

    public let clusterTimeGap: TimeInterval
    public let minimumClusterWeight: Double
    public let minimumBlockDuration: TimeInterval
    public let temporalPadding: TimeInterval
    public let targetPadding: Double
    public let minimumZoom: Double
    public let maximumZoom: Double
    public let dwellDurationThreshold: TimeInterval
    public let dwellMovementTolerance: Double
    public let maxProposals: Int

    public init(
        clusterTimeGap: TimeInterval = 2.5,
        minimumClusterWeight: Double = 1.5,
        minimumBlockDuration: TimeInterval = 1.5,
        temporalPadding: TimeInterval = 0.25,
        targetPadding: Double = 0.08,
        minimumZoom: Double = 1.2,
        maximumZoom: Double = 3,
        dwellDurationThreshold: TimeInterval = 1.5,
        dwellMovementTolerance: Double = 0.03,
        maxProposals: Int = 40
    ) throws {
        guard clusterTimeGap.isFinite,
            clusterTimeGap > 0,
            minimumClusterWeight.isFinite,
            minimumClusterWeight > 0,
            minimumBlockDuration.isFinite,
            minimumBlockDuration > 0,
            temporalPadding.isFinite,
            temporalPadding >= 0,
            targetPadding.isFinite,
            targetPadding >= 0,
            minimumZoom.isFinite,
            maximumZoom.isFinite,
            minimumZoom >= 1,
            maximumZoom <= 3,
            minimumZoom <= maximumZoom,
            dwellDurationThreshold.isFinite,
            dwellDurationThreshold > 0,
            dwellMovementTolerance.isFinite,
            dwellMovementTolerance >= 0,
            maxProposals > 0
        else {
            throw ZoomPanModelError.invalidProposalTuning
        }

        self.init(
            uncheckedClusterTimeGap: clusterTimeGap,
            minimumClusterWeight: minimumClusterWeight,
            minimumBlockDuration: minimumBlockDuration,
            temporalPadding: temporalPadding,
            targetPadding: targetPadding,
            minimumZoom: minimumZoom,
            maximumZoom: maximumZoom,
            dwellDurationThreshold: dwellDurationThreshold,
            dwellMovementTolerance: dwellMovementTolerance,
            maxProposals: maxProposals
        )
    }

    private init(
        uncheckedClusterTimeGap clusterTimeGap: TimeInterval,
        minimumClusterWeight: Double,
        minimumBlockDuration: TimeInterval,
        temporalPadding: TimeInterval,
        targetPadding: Double,
        minimumZoom: Double,
        maximumZoom: Double,
        dwellDurationThreshold: TimeInterval,
        dwellMovementTolerance: Double,
        maxProposals: Int
    ) {
        self.clusterTimeGap = clusterTimeGap
        self.minimumClusterWeight = minimumClusterWeight
        self.minimumBlockDuration = minimumBlockDuration
        self.temporalPadding = temporalPadding
        self.targetPadding = targetPadding
        self.minimumZoom = minimumZoom
        self.maximumZoom = maximumZoom
        self.dwellDurationThreshold = dwellDurationThreshold
        self.dwellMovementTolerance = dwellMovementTolerance
        self.maxProposals = maxProposals
    }
}
