import Foundation

struct Tweet: Equatable, Sendable {
    let id: String
    let text: String
    let username: String
    let url: URL
    let createdAt: Date
    let kind: String

    var isOriginalEnoughForAlert: Bool {
        let normalized = kind.lowercased()
        return !["reply", "repost", "retweet", "like", "mention", "follow"].contains(normalized)
    }
}

enum ResetSignal: String, Equatable, Sendable {
    case confirmed
}

struct CoinAlert: Equatable, Sendable {
    let signal: ResetSignal
    let tweet: Tweet
}

enum MonitorState: Equatable, Sendable {
    case starting
    case polling
    case checking
    case offline(String)
    case missingServerEndpoint

    var menuText: String {
        switch self {
        case .starting:
            return "● Connecting to Tibo radar…"
        case .polling:
            return "● Connected to central server"
        case .checking:
            return "● Checking…"
        case .offline(let reason):
            return "● Offline: \(reason)"
        case .missingServerEndpoint:
            return "● Central server is not configured"
        }
    }
}
