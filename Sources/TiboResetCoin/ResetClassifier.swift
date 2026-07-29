import Foundation

enum ResetClassifier {
    private static let productTerms = [
        "chatgpt",
        "codex"
    ]

    private static let allowanceTerms = [
        "usage limit",
        "usage limits",
        "rate limit",
        "rate limits",
        "weekly limit",
        "weekly limits",
        "quota",
        "banked reset",
        "usage cap",
        "usage caps",
        "allowance"
    ]

    private static let completedTerms = [
        "have now been reset",
        "has now been reset",
        "have been reset",
        "has been reset",
        "were reset",
        "was reset",
        "are now reset",
        "is now reset",
        "just reset",
        "we reset",
        "i reset",
        "reset is complete",
        "reset completed",
        "added a banked reset",
        "refilled",
        "replenished",
        "have been restored",
        "has been restored",
        "limits restored",
        "quota restored"
    ]

    private static let rejectedTerms = [
        "will reset",
        "will be reset",
        "going to reset",
        "plan to reset",
        "planning to reset",
        "should reset",
        "may reset",
        "might reset",
        "can reset",
        "could reset",
        "reset later",
        "reset this evening",
        "reset tonight",
        "reset tomorrow",
        "reset soon",
        "reset in ",
        "reset within ",
        "reset is coming",
        "reset coming",
        "working on",
        "trying to",
        "not reset",
        "not been reset",
        "haven't reset",
        "hasn't reset",
        "didn't reset",
        "did not reset",
        "won't reset",
        "can't reset",
        "cannot reset",
        "unable to reset",
        "no reset"
    ]

    static func classify(_ text: String) -> ResetSignal? {
        let normalized = text
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !normalized.contains("?") else {
            return nil
        }
        guard !rejectedTerms.contains(where: normalized.contains) else {
            return nil
        }
        guard productTerms.contains(where: normalized.contains) else {
            return nil
        }
        guard allowanceTerms.contains(where: normalized.contains) else {
            return nil
        }
        guard completedTerms.contains(where: normalized.contains) else {
            return nil
        }

        return .confirmed
    }
}
