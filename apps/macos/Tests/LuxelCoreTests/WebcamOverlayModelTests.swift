import Foundation
import LuxelCore
import Testing

@Suite("Webcam overlay models")
struct WebcamOverlayModelTests {
    @Test("camera shapes preserve legacy values and stable display order")
    func cameraShapesPreserveLegacyValuesAndStableDisplayOrder() throws {
        #expect(CameraOverlayShape.allCases == [.circle, .roundedRect, .square])
        #expect(try JSONDecoder().decode(CameraOverlayShape.self, from: Data(#""circle""#.utf8)) == .circle)
        #expect(
            try JSONDecoder().decode(
                CameraOverlayShape.self,
                from: Data(#""roundedRect""#.utf8)
            ) == .roundedRect
        )
        let legacyCutout = try JSONDecoder().decode(
            CameraPreviewStyle.self,
            from: Data(#"{"shape":"cutout","size":"large","isMirrored":false}"#.utf8)
        )
        #expect(legacyCutout.shape == .circle)
        #expect(legacyCutout.backgroundEffect == .portraitCutout)

        let encodedPlan = try JSONEncoder().encode(CameraOverlayPlan())
        var legacyPlanObject = try #require(
            JSONSerialization.jsonObject(with: encodedPlan) as? [String: Any]
        )
        legacyPlanObject["shape"] = "cutout"
        legacyPlanObject.removeValue(forKey: "backgroundEffect")
        let legacyPlan = try JSONDecoder().decode(
            CameraOverlayPlan.self,
            from: JSONSerialization.data(withJSONObject: legacyPlanObject)
        )
        #expect(legacyPlan.shape == .circle)
        #expect(legacyPlan.backgroundEffect == .portraitCutout)
    }

    @Test("camera shapes and background effects round trip independently")
    func cameraShapesAndBackgroundEffectsRoundTripIndependently() throws {
        for shape in CameraOverlayShape.allCases {
            for backgroundEffect in CameraBackgroundEffect.allCases {
                let options = CameraRecordingOptions(
                    deviceID: "camera-1",
                    isEnabled: true,
                    previewStyle: CameraPreviewStyle(
                        shape: shape,
                        size: .large,
                        isMirrored: false,
                        backgroundEffect: backgroundEffect
                    )
                )
                let decodedOptions = try JSONDecoder().decode(
                    CameraRecordingOptions.self,
                    from: JSONEncoder().encode(options)
                )
                #expect(decodedOptions == options)

                let plan = try CameraOverlayPlan(
                    shape: shape,
                    backgroundEffect: backgroundEffect
                )
                let decodedPlan = try JSONDecoder().decode(
                    CameraOverlayPlan.self,
                    from: JSONEncoder().encode(plan)
                )
                #expect(decodedPlan == plan)
            }
        }
    }

    @Test("camera recording options expose defaults and normalize empty device ID")
    func cameraRecordingOptionsExposeDefaults() {
        let defaults = CameraRecordingOptions()
        let enabled = CameraRecordingOptions(
            deviceID: "",
            isEnabled: true,
            recordsSeparateTrack: false,
            previewStyle: CameraPreviewStyle(shape: .roundedRect, size: .large, isMirrored: false)
        )

        #expect(defaults.deviceID == nil)
        #expect(!defaults.isEnabled)
        #expect(defaults.recordsSeparateTrack)
        #expect(defaults.previewStyle == CameraPreviewStyle())
        #expect(enabled.deviceID == nil)
        #expect(enabled.isEnabled)
        #expect(!enabled.recordsSeparateTrack)
        #expect(enabled.previewStyle.shape == .roundedRect)
        #expect(enabled.previewStyle.size == .large)
        #expect(!enabled.previewStyle.isMirrored)
    }

    @Test("overlay plan validates width fraction and normalized point")
    func overlayPlanValidatesWidthFractionAndNormalizedPoint() throws {
        _ = try CameraOverlayPlan(widthFraction: 0.15)
        _ = try CameraOverlayPlan(widthFraction: 0.4)
        _ = try NormalizedPoint(x: 0, y: 1)

        #expect(throws: WebcamOverlayModelError.invalidWidthFraction) {
            _ = try CameraOverlayPlan(widthFraction: 0.14)
        }
        #expect(throws: WebcamOverlayModelError.invalidWidthFraction) {
            _ = try CameraOverlayPlan(widthFraction: 0.41)
        }
        #expect(throws: WebcamOverlayModelError.invalidWidthFraction) {
            _ = try CameraOverlayPlan(widthFraction: .infinity)
        }
        #expect(throws: WebcamOverlayModelError.invalidNormalizedPoint) {
            _ = try NormalizedPoint(x: -0.1, y: 0.5)
        }
        #expect(throws: WebcamOverlayModelError.invalidNormalizedPoint) {
            _ = try NormalizedPoint(x: 0.5, y: .infinity)
        }
    }

    @Test("anchored overlay resolves pixel rect with proportional margin")
    func anchoredOverlayResolvesPixelRect() throws {
        let outputSize = try PixelSize(width: 1920, height: 1080)
        let topLeft = try CameraOverlayPlan(
            placement: .anchor(.topLeft),
            widthFraction: 0.25
        )
        let bottomRight = try CameraOverlayPlan(
            placement: .anchor(.bottomRight),
            widthFraction: 0.25
        )

        #expect(try topLeft.rect(in: outputSize) == CaptureRect(x: 58, y: 58, width: 480, height: 480))
        #expect(
            try bottomRight.rect(in: outputSize) == CaptureRect(x: 1382, y: 542, width: 480, height: 480))
    }

    @Test("normalized overlay resolves around center point")
    func normalizedOverlayResolvesAroundCenterPoint() throws {
        let outputSize = try PixelSize(width: 1280, height: 720)
        let plan = try CameraOverlayPlan(
            placement: .normalizedPoint(NormalizedPoint(x: 0.5, y: 0.5)),
            widthFraction: 0.2,
            shape: .roundedRect,
            showsBorder: false
        )

        #expect(try plan.rect(in: outputSize) == CaptureRect(x: 512, y: 232, width: 256, height: 256))
        #expect(plan.shape == .roundedRect)
        #expect(!plan.showsBorder)
    }

    @Test("overlay rejects placements outside output frame")
    func overlayRejectsPlacementsOutsideOutputFrame() throws {
        let smallOutput = try PixelSize(width: 20, height: 20)
        let anchored = try CameraOverlayPlan(placement: .anchor(.bottomRight), widthFraction: 0.4)
        let normalized = try CameraOverlayPlan(
            placement: .normalizedPoint(NormalizedPoint(x: 0.05, y: 0.5)),
            widthFraction: 0.4
        )

        #expect(throws: WebcamOverlayModelError.overlayOutsideFrame) {
            _ = try anchored.rect(in: smallOutput)
        }
        #expect(throws: WebcamOverlayModelError.overlayOutsideFrame) {
            _ = try normalized.rect(in: smallOutput)
        }
    }
}
