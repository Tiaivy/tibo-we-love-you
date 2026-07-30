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

@Test
@MainActor
func formatsTimeSinceLastReset() throws {
    let resetDate = try #require(
        ResetFeedClient.date(from: "2026-07-28T08:00:00.000Z")
    )
    let now = try #require(
        ResetFeedClient.date(from: "2026-07-30T12:15:00.000Z")
    )

    #expect(
        CheckStatusCopy.elapsed(since: resetDate, now: now)
            == "2 days, 4 hours ago"
    )
}

@Test
@MainActor
func manualCheckShowsStatusOnlyWhenNothingIsNew() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let client = ResetFeedClient(
        endpoint: URL(string: "https://example.com/v1/reset/latest")!,
        session: URLSession(configuration: configuration)
    )

    StubURLProtocol.payload = """
    {
      "version": 1,
      "source": "thsottiaux",
      "checkedAt": "2026-07-30T12:30:00.000Z",
      "lastResetAt": "2026-07-28T08:00:00.000Z",
      "event": null
    }
    """.data(using: .utf8)!

    let statusSuite = "TiboResetCoinTests.status.\(UUID())"
    let statusDefaults = try #require(UserDefaults(suiteName: statusSuite))
    defer {
        statusDefaults.removePersistentDomain(forName: statusSuite)
    }
    let statusMonitor = MonitorService(
        defaults: statusDefaults,
        client: client
    )
    var statusDate: Date?
    var alertCount = 0
    statusMonitor.onCheckStatus = { statusDate = $0 }
    statusMonitor.onAlert = { _ in alertCount += 1 }

    await statusMonitor.checkNow(showStatus: true)

    #expect(
        statusDate
            == ResetFeedClient.date(
                from: "2026-07-28T08:00:00.000Z"
            )
    )
    #expect(alertCount == 0)

    StubURLProtocol.payload = """
    {
      "version": 1,
      "source": "thsottiaux",
      "checkedAt": "2026-07-30T12:40:00.000Z",
      "lastResetAt": "2026-07-30T12:39:00.000Z",
      "event": {
        "id": "new-reset",
        "signal": "confirmed",
        "text": "ChatGPT and Codex limits have been reset.",
        "url": "https://x.com/thsottiaux/status/new-reset",
        "createdAt": "2026-07-30T12:39:00.000Z"
      }
    }
    """.data(using: .utf8)!

    let alertSuite = "TiboResetCoinTests.alert.\(UUID())"
    let alertDefaults = try #require(UserDefaults(suiteName: alertSuite))
    defer {
        alertDefaults.removePersistentDomain(forName: alertSuite)
    }
    let alertMonitor = MonitorService(
        defaults: alertDefaults,
        client: client
    )
    var secondStatusCount = 0
    var secondAlertCount = 0
    alertMonitor.onCheckStatus = { _ in secondStatusCount += 1 }
    alertMonitor.onAlert = { _ in secondAlertCount += 1 }

    await alertMonitor.checkNow(showStatus: true)

    #expect(secondStatusCount == 0)
    #expect(secondAlertCount == 1)
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(
        for request: URLRequest
    ) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
