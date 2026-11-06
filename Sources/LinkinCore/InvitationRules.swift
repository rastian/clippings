import Foundation

public enum InvitationRules {
    public static func validate(container: String, expected: String, currentUser: String, boundUser: String?) throws {
        guard container == expected else { throw LinkinError.validation("This invitation belongs to another app.") }
        guard !currentUser.isEmpty else { throw LinkinError.validation("Sign in to iCloud before accepting an invitation.") }
        if let boundUser, boundUser != currentUser { throw LinkinError.accountChanged }
    }
}
