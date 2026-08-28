import Foundation

enum LuxelCommandLineAutomationError: LocalizedError {
    case controlDisabled
    case pairingDenied
    case folderSelectionCanceled
    case unknownClient
    case invalidAuthentication
    case expiredRequest
    case replayedRequest
    case requestDigestMismatch
    case requestIDMismatch
    case fileAccessRequired(String)
    case fileAccessRevoked(String)
    case missingArguments
    case commandUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .controlDisabled:
            "Command-line control is disabled in Luxel Settings."
        case .pairingDenied:
            "Pairing was denied in Luxel."
        case .folderSelectionCanceled:
            "No folder was selected."
        case .unknownClient:
            "This command-line client is not paired with Luxel. Run `luxel pair`."
        case .invalidAuthentication:
            "The command-line request could not be authenticated. Run `luxel pair` again."
        case .expiredRequest:
            "The command-line request expired before Luxel received it."
        case .replayedRequest:
            "Luxel rejected a repeated command-line request."
        case .requestDigestMismatch:
            "The command-line request body did not match its signed digest."
        case .requestIDMismatch:
            "The command-line request identifier did not match its callback."
        case .fileAccessRequired(let path):
            "Luxel does not have access to \(path). Run `luxel access add \"\(path)\"`."
        case .fileAccessRevoked(let path):
            "Luxel's folder access was revoked for \(path). Add the folder again."
        case .missingArguments:
            "The command-line request is missing required arguments."
        case .commandUnavailable(let command):
            "The \(command) command is not available in this version of Luxel."
        }
    }

    var code: String {
        switch self {
        case .controlDisabled: "control_disabled"
        case .pairingDenied: "pairing_denied"
        case .folderSelectionCanceled: "folder_selection_canceled"
        case .unknownClient: "not_paired"
        case .invalidAuthentication: "authentication_failed"
        case .expiredRequest: "request_expired"
        case .replayedRequest: "request_replayed"
        case .requestDigestMismatch: "digest_mismatch"
        case .requestIDMismatch: "request_id_mismatch"
        case .fileAccessRequired: "file_access_required"
        case .fileAccessRevoked: "file_access_revoked"
        case .missingArguments: "invalid_request"
        case .commandUnavailable: "command_unavailable"
        }
    }
}
