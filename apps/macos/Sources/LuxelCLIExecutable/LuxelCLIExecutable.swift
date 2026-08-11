import Darwin
import Foundation
import LuxelCLI
import LuxelCore

@main
enum LuxelCLIExecutable {
    static func main() async {
        #if LUXEL_MAC_APP_STORE
        let purchaseGate = MacAppStorePaidAppPurchaseGate(
            currentBundleID: { "com.rawcontext.luxel" }
        )
        guard await purchaseGate.isEntitled() else {
            let title = LuxelLocalization.string(
                "purchaseVerification.failed.title",
                defaultValue: "Luxel Purchase Could Not Be Verified"
            )
            let message = LuxelLocalization.string(
                "purchaseVerification.failed.message",
                defaultValue:
                    "Install Luxel from the Mac App Store using the Apple Account that purchased it."
            )
            FileHandle.standardError.write(Data("\(title)\n\(message)\n".utf8))
            Darwin.exit(EX_NOPERM)
        }
        #endif

        LuxelCLI.main()
    }
}
