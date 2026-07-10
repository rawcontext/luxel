import CoreMedia
import Foundation
import ScreenCaptureKit

enum ReplayBufferSampleAttachments {
    static func first(from sampleBuffer: CMSampleBuffer) -> [AnyHashable: Any]? {
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            )
        else {
            return nil
        }
        if let typedAttachments = attachmentsArray as? [[AnyHashable: Any]],
           let attachments = typedAttachments.first {
            return attachments
        }
        let firstAttachment = (attachmentsArray as NSArray).firstObject
        if let attachments = firstAttachment as? [SCStreamFrameInfo: Any] {
            return Dictionary(uniqueKeysWithValues: attachments.map { (AnyHashable($0.key), $0.value) })
        }
        if let attachments = firstAttachment as? [AnyHashable: Any] {
            return attachments
        }
        guard let attachments = firstAttachment as? NSDictionary else {
            return nil
        }
        var result: [AnyHashable: Any] = [:]
        for (key, value) in attachments {
            if let key = key as? SCStreamFrameInfo {
                result[AnyHashable(key)] = value
            } else if let key = key as? String {
                result[AnyHashable(key)] = value
            } else if let key = key as? NSString {
                result[AnyHashable(key as String)] = value
            }
        }
        return result.isEmpty ? nil : result
    }

    static func statusRawValue(from attachments: [AnyHashable: Any]) -> Int? {
        let value = attachments[AnyHashable(SCStreamFrameInfo.status)]
            ?? attachments[AnyHashable(SCStreamFrameInfo.status.rawValue)]
        if let value = value as? SCFrameStatus {
            return value.rawValue
        }
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }
}

struct ReplayBufferSegmentTiming {
    let start: TimeInterval
    let duration: TimeInterval
}

enum ReplayBufferSegmentStorageEvent: Equatable {
    case clipBecameAvailable
}

struct ReplayBufferClipPlan: Sendable {
    let outputURL: URL
    let initializationSegmentData: Data
    let segmentFileURLs: [URL]
    let segmentIDs: Set<String>
    let trimStartOffset: TimeInterval?
    let requestedDuration: TimeInterval
}
