import Foundation

public enum AutomationURLScheme {
    public static let production = "luxel"

    public static func registered(containing executableURL: URL?) -> String {
        guard let executableURL,
              let appBundleURL = MacAppStorePaidAppPurchaseGate.enclosingAppBundleURL(
                containing: executableURL
              ),
              executableURL.resolvingSymlinksInPath().deletingLastPathComponent().path
                == appBundleURL.appending(path: "Contents/MacOS").path,
              let bundle = Bundle(url: appBundleURL)
        else {
            return production
        }
        return registered(in: bundle.infoDictionary)
    }

    public static func registered(in infoDictionary: [String: Any]?) -> String {
        let urlTypes = infoDictionary?["CFBundleURLTypes"] as? [[String: Any]]
        let schemes = urlTypes?.compactMap { $0["CFBundleURLSchemes"] as? [String] }.flatMap(\.self)
        return schemes?.first(where: { !$0.isEmpty }) ?? production
    }
}
