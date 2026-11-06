import Foundation

public enum InvitationRules {
    public static func validate(container: String, expected: String, currentUser: String, boundUser: String?) throws {
        guard container == expected else { throw ClippingsError.validation("This invitation belongs to another app.") }
        guard !currentUser.isEmpty else { throw ClippingsError.validation("Sign in to iCloud before accepting an invitation.") }
        if let boundUser, boundUser != currentUser { throw ClippingsError.accountChanged }
    }
}
