import Foundation
import LuxelCore

struct ScreenshotThumbnailItem: Equatable {
    let imageData: ImageData
    let fileName: String
    let fileURL: URL?
}

@MainActor
protocol ScreenshotThumbnailPresenter: AnyObject {
    func present(_ item: ScreenshotThumbnailItem)
}
