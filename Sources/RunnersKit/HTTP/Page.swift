import Foundation

/// A list response body. A bare JSON array is one; so is an object wrapping the list.
public protocol PagedResponse: Decodable {
    associatedtype Item
    var items: [Item] { get }
}

extension Array: PagedResponse where Element: Decodable {
    public var items: [Element] { self }
}

/// One page of a list, and where the next one is.
struct Page<Item> {
    let items: [Item]
    let next: URL?

    static func decode<P: PagedResponse>(
        _ type: P.Type,
        from response: HTTPResponse
    ) -> Result<Page<P.Item>, RunnersError> where P.Item == Item {
        JSONCoding.decode(type, from: response.body)
            .map { Page(items: $0.items, next: LinkHeader.next(in: response.header("link"))) }
    }
}
