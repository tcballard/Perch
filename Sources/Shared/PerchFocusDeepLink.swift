import Foundation

enum PerchFocusDeepLink {
    static let scheme = "perch"

    static func widgetURL(for nativeURL: URL) -> URL? {
        guard nativeURL.scheme == "codex",
              nativeURL.host == "threads",
              UUID(uuidString: nativeURL.lastPathComponent) != nil
        else { return nil }

        return URL(string: "\(scheme)://focus/codex/\(nativeURL.lastPathComponent)")
    }

    static func nativeURL(from widgetURL: URL) -> URL? {
        let path = widgetURL.pathComponents.filter { $0 != "/" }
        guard widgetURL.scheme == scheme,
              widgetURL.host == "focus",
              path.count == 2,
              path[0] == "codex",
              UUID(uuidString: path[1]) != nil
        else { return nil }

        return URL(string: "codex://threads/\(path[1])")
    }
}
