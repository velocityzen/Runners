import Foundation
import Testing

@testable import RunnersKit

@Suite("Link header")
struct LinkHeaderTests {
    @Test("finds the next page among other relations")
    func next() {
        let header =
            #"<https://api.github.com/user/repos?page=1>; rel="prev", <https://api.github.com/user/repos?page=3>; rel="next", <https://api.github.com/user/repos?page=9>; rel="last""#
        #expect(
            LinkHeader.next(in: header)?.absoluteString
                == "https://api.github.com/user/repos?page=3"
        )
    }

    @Test("has no next page on the last page or without a header")
    func last() {
        #expect(LinkHeader.next(in: #"<https://api.github.com/x?page=1>; rel="first""#) == nil)
        #expect(LinkHeader.next(in: nil) == nil)
    }
}
