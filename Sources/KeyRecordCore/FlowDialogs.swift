import Foundation

// MARK: - Two-stage confirmation dialogs (task 18)

/// At most one destructive flow dialog is presented at a time; `none` dismisses it.
public enum FlowDialog: Equatable, Sendable {
    case none
    case resetConfirmation(ResetProposal)
    case deleteConfirmation(DeleteProposal)
}

/// The single user decision captured by a presented dialog.
public enum DialogChoice: Equatable, Sendable {
    case cancel
    case confirm
}

/// Failures a dialog confirmation can surface to the UI.
public enum FlowError: Error, Equatable, Sendable {
    /// No adapter is wired for the confirmed action; the UI disables/explains the affordance.
    case actionUnavailable
}

/// Localized content for the "reset today" dialog. Keys are stable snake-case ids that
/// map one-to-one to rows in Localizable.strings; Core never stores user-facing prose.
public struct ResetProposal: Equatable, Sendable {
    public let titleKey: String
    public let messageKey: String
    public let confirmKey: String
    public let cancelKey: String

    public init(titleKey: String, messageKey: String, confirmKey: String, cancelKey: String) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.confirmKey = confirmKey
        self.cancelKey = cancelKey
    }

    /// Copy contract: deletes the day-level detail rows for the active cycle, while
    /// mappings, backups, preferences, and ignored recommendations are retained.
    public static func standard() -> ResetProposal {
        ResetProposal(titleKey: "dialog.reset.title",
                      messageKey: "dialog.reset.message",
                      confirmKey: "dialog.reset.confirm",
                      cancelKey: "dialog.reset.cancel")
    }
}

/// Localized content for the "delete all local data" dialog.
public struct DeleteProposal: Equatable, Sendable {
    public let titleKey: String
    public let messageKey: String
    public let confirmKey: String
    public let cancelKey: String

    public init(titleKey: String, messageKey: String, confirmKey: String, cancelKey: String) {
        self.titleKey = titleKey
        self.messageKey = messageKey
        self.confirmKey = confirmKey
        self.cancelKey = cancelKey
    }

    /// Copy contract: the action is irreversible and removes every local artifact —
    /// aggregates and mappings, the namespace keys, and the login item registration.
    public static func deleteStandard() -> DeleteProposal {
        DeleteProposal(titleKey: "dialog.delete.title",
                       messageKey: "dialog.delete.message",
                       confirmKey: "dialog.delete.confirm",
                       cancelKey: "dialog.delete.cancel")
    }
}
