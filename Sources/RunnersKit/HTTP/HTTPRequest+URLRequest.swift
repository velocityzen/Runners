import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

extension HTTPRequest {
    var urlRequest: URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
