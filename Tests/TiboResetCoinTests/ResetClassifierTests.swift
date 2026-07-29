import Foundation
import Testing
@testable import TiboResetCoin

@Test
func detectsCompletedReset() {
    #expect(
        ResetClassifier.classify(
            "Codex usage limits have now been reset across all paid plans. Enjoy!"
        ) == .confirmed
    )
}

@Test
func ignoresScheduledReset() {
    #expect(
        ResetClassifier.classify(
            "I will reset usage limits this evening after we confirm the fix."
        ) == nil
    )
}

@Test
func detectsBankedReset() {
    #expect(
        ResetClassifier.classify(
            "Added a banked reset to 500k users of ChatGPT Work and Codex."
        ) == .confirmed
    )
}

@Test
func ignoresUnrelatedReset() {
    #expect(
        ResetClassifier.classify(
            "Reset your password before signing into the dashboard."
        ) == nil
    )
}

@Test
func ignoresOrdinaryCodexPost() {
    #expect(
        ResetClassifier.classify(
            "Codex is now much faster at working across large repositories."
        ) == nil
    )
}

@Test
func ignoresNegatedReset() {
    #expect(
        ResetClassifier.classify(
            "Codex usage limits have not been reset yet."
        ) == nil
    )
}

@Test
func ignoresQuestionAboutReset() {
    #expect(
        ResetClassifier.classify(
            "Have ChatGPT Work usage limits been reset?"
        ) == nil
    )
}

@Test
func requiresProductAndAllowanceContext() {
    #expect(
        ResetClassifier.classify(
            "Usage limits have now been reset for all paid users."
        ) == nil
    )
    #expect(
        ResetClassifier.classify(
            "Codex has now been reset."
        ) == nil
    )
}

@Test
func loadsHTTPSCentralFeedFromEnvironment() throws {
    let url = try FeedEndpointProvider.load(
        environment: [
            FeedEndpointProvider.environmentKey:
                "https://example.com/v1/reset/latest"
        ]
    )
    #expect(url.absoluteString == "https://example.com/v1/reset/latest")
}

@Test
@MainActor
func parsesCentralFeedTimestamp() {
    let date = ResetFeedClient.date(from: "2026-07-29T00:06:00.000Z")
    #expect(date != nil)
}
