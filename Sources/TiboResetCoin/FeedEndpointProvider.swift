import Foundation

enum FeedEndpointProvider {
    static let infoPlistKey = "TiboResetFeedURL"
    static let environmentKey = "TIBO_RESET_FEED_URL"

    static func load(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        let rawValue = environment[environmentKey]
            ?? bundle.object(forInfoDictionaryKey: infoPlistKey) as? String
            ?? ""
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            url.scheme == "https",
            url.host != nil
        else {
            throw FeedEndpointError.missingURL
        }
        return url
    }
}

enum FeedEndpointError: LocalizedError {
    case missingURL

    var errorDescription: String? {
        "Tibo, We Love You server URL is not configured"
    }
}
