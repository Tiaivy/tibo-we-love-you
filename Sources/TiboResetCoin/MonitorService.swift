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

    private(set) var state: MonitorState = .starting {
        didSet { onStateChange?(state) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    func checkNow(seedIfNeeded: Bool = false) async {
        guard let client else {
            if state != .missingServerEndpoint {
                start()
            }
            return
        }

        state = .checking
        do {
            let snapshot = try await client.fetchLatest()
            process(
                snapshot,
                seedOnly: seedIfNeeded && isFirstFeedCheck
            )
            state = .polling
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

    private func process(_ snapshot: ResetFeedSnapshot, seedOnly: Bool) {
        guard let event = snapshot.event else {
            isFirstFeedCheck = false
            return
        }
        if seedOnly {
            seenTweetIDs.insert(event.id)
            isFirstFeedCheck = false
            persistSeenIDs()
            return
        }

        guard !seenTweetIDs.contains(event.id) else {
            return
        }
        seenTweetIDs.insert(event.id)
        isFirstFeedCheck = false

        guard
            event.signal == ResetSignal.confirmed.rawValue,
            let url = URL(string: event.url)
        else {
            persistSeenIDs()
            return
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
