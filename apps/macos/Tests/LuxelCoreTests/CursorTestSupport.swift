import Foundation
import LuxelCore

func testCursorImage(
    id: String = "arrow",
    pngData: Data = Data([0x89, 0x50, 0x4E, 0x47]),
    hotspot: CursorPoint? = nil
) throws -> CursorImageAsset {
    try CursorImageAsset(
        id: id,
        pngData: pngData,
        hotspot: try hotspot ?? CursorPoint(x: 1, y: 1),
        scale: 2
    )
}

func testCursorSample(
    time: TimeInterval,
    x xCoordinate: Double,
    y yCoordinate: Double
) throws -> CursorSample {
    try CursorSample(
        time: time,
        position: CursorPoint(x: xCoordinate, y: yCoordinate),
        cursorImageID: "arrow"
    )
}
