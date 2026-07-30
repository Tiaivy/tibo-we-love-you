import Foundation

@MainActor
final class MonitorService {
    private enum DefaultsKey {
        static let seenTweetIDs = "seenTweetIDs"
    }

    private let defaults: UserDefaults
    private var client: ResetFeedClient?
    private var pollingTask: Task<Void, Never>?
    private var seenTweetIDs: Set<String>
    private var isFirstFeedCheck: Bool

    var onStateChange: ((MonitorState) -> Void)?
    var onAlert: ((CoinAlert) -> Void)?
    var onCheckStatus: ((Date?) -> Void)?

    private(set) var state: MonitorState = .starting {
        didSet { onStateChange?(state) }
    }

    init(
        defaults: UserDefaults = .standard,
        client: ResetFeedClient? = nil
    ) {
        self.defaults = defaults
        self.client = client
        let saved = defaults.stringArray(forKey: DefaultsKey.seenTweetIDs) ?? []
        self.seenTweetIDs = Set(saved)
        self.isFirstFeedCheck = saved.isEmpty
    }

    func start() {
        state = .starting

        let endpoint: URL
        do {
            endpoint = try FeedEndpointProvider.load()
        } catch {
            state = .missingServerEndpoint
            return
        }

        let client = ResetFeedClient(endpoint: endpoint)
        self.client = client
        state = .polling
        startPolling()
        Task {
            await checkNow(seedIfNeeded: true)
        }
    }

    func checkNow(
        seedIfNeeded: Bool = false,
        showStatus: Bool = false
    ) async {
        guard let client else {
            if state != .missingServerEndpoint {
                start()
            }
            return
        }

        state = .checking
        do {
            let snapshot = try await client.fetchLatest()
            let didAlert = process(
                snapshot,
                seedOnly: seedIfNeeded && isFirstFeedCheck
            )
            state = .polling
            if showStatus && !didAlert {
                onCheckStatus?(
                    ResetFeedClient.date(from: snapshot.lastResetAt)
                )
            }
        } catch {
            state = .offline(
                (error as? LocalizedError)?.errorDescription ?? "Check failed"
            )
        }
    }

    func stop() {
        pollingTask?.cancel()
    }

    func testAlert() {
        let tweet = Tweet(
            id: "demo",
            text: "Codex and ChatGPT Work usage limits have now been reset for all paid users. Enjoy!",
            username: "thsottiaux",
            url: URL(string: "https://x.com/thsottiaux")!,
            createdAt: Date(),
            kind: "post"
        )
        onAlert?(CoinAlert(signal: .confirmed, tweet: tweet))
    }

    @discardableResult
    private func process(
        _ snapshot: ResetFeedSnapshot,
        seedOnly: Bool
    ) -> Bool {
        guard let event = snapshot.event else {
            isFirstFeedCheck = false
            return false
        }
        if seedOnly {
            seenTweetIDs.insert(event.id)
            isFirstFeedCheck = false
            persistSeenIDs()
            return false
        }

        guard !seenTweetIDs.contains(event.id) else {
            return false
        }
        seenTweetIDs.insert(event.id)
        isFirstFeedCheck = false

        guard
            event.signal == ResetSignal.confirmed.rawValue,
            let url = URL(string: event.url)
        else {
            persistSeenIDs()
            return false
        }

        let tweet = Tweet(
            id: event.id,
            text: event.text,
            username: snapshot.source,
            url: url,
            createdAt:
                ResetFeedClient.date(from: event.createdAt) ?? Date(),
            kind: "post"
        )
        let alert = CoinAlert(signal: .confirmed, tweet: tweet)
        onAlert?(alert)
        persistSeenIDs()
        return true
    }

    private func persistSeenIDs() {
        let limited = Array(seenTweetIDs.sorted().suffix(300))
        defaults.set(limited, forKey: DefaultsKey.seenTweetIDs)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled, let self else { return }
                await self.checkNow()
            }
        }
    }
}
