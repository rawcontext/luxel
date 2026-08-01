import LuxelCore

func testNotchRect(
    x originX: Double,
    y originY: Double,
    width: Double,
    height: Double
) throws -> NotchScreenRect {
    try NotchScreenRect(x: originX, y: originY, width: width, height: height)
}

func testBuiltInNotchedDisplay(
    displayID: DisplayID = DisplayID(1),
    safeAreaTopInset: Double = 34,
    isBuiltIn: Bool = true,
    isVisible: Bool = true
) throws -> NotchDisplayDescriptor {
    try NotchDisplayDescriptor(
        displayID: displayID,
        frame: testNotchRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NotchSafeAreaInsets(top: safeAreaTopInset),
        auxiliaryTopLeftArea: testNotchRect(x: 0, y: 948, width: 640, height: 34),
        auxiliaryTopRightArea: testNotchRect(x: 872, y: 948, width: 640, height: 34),
        isBuiltIn: isBuiltIn,
        isVisible: isVisible
    )
}
