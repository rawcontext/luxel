import Foundation

@MainActor
extension LuxelMenuModel {
    func errorMessage(_ error: Error) -> String {
        errorReporter.record(error, context: "menu")
        let description = (error as NSError).localizedDescription
        return description.isEmpty ? String(describing: error) : description
    }
}
