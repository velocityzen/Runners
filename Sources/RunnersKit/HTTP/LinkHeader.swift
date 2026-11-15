import Foundation

/// Reads the pagination `Link` header GitHub and GitLab send:
/// `<https://api.github.com/…&page=2>; rel="next", <…>; rel="last"`.
enum LinkHeader {
    static func next(in header: String?) -> URL? {
        header?
            .split(separator: ",")
            .first { $0.contains("rel=\"next\"") }
            .flatMap(target)
    }

    private static func target(of link: Substring) -> URL? {
        link.split(separator: ";")
            .first
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " <>")) }
            .flatMap(URL.init(string:))
    }
}
