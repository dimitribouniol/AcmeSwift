import Foundation
import NIO
import AsyncHTTPClient
import Logging

extension HTTPClientResponse {
    
    public enum BodyError : Swift.Error, Sendable {
        case noBodyData
    }
    
    /// Decode the response body as T using the given decoder.
    ///
    /// - parameters:
    ///     - type: The type to decode.  Must conform to Decoable.
    ///     - decoder: The decoder used to decode the reponse body.  Defaults to JSONDecoder.
    /// - returns: A future decoded type.
    /// - throws: BodyError.noBodyData when no body is found in reponse.
    public func decode<T : Decodable>(as type: T.Type, decoder: Decoder = JSONDecoder()) async throws -> T {
        try await checkStatusCode()
        
        var body = try await self.body.collect(upTo: 2 * 1024 * 1024) // 2 MB
        if T.self == NoBody.self || T.self == NoBody?.self {
            return NoBody() as! T
        }
        
        guard let data = body.readData(length: body.readableBytes) else {
            throw AcmeError.dataCorrupted("Unable to read Data from response body buffer")
        }
        if T.self == String.self {
            return String(decoding: data, as: UTF8.self) as! T
        }
        
        return try decoder.decode(type, from: Data(data))
    }
    
    fileprivate func checkStatusCode() async throws {
        guard 200...299 ~= self.status.code else {
            var body = try await self.body.collect(upTo: 1 * 1024 * 1024)
            
            if let data = body.readData(length: body.readableBytes) {
                if let error = try? JSONDecoder().decode(AcmeResponseError.self, from: data) {
                    throw error
                }
                throw AcmeError.errorCode(self.status.code, String(decoding: data, as: UTF8.self))
            }
            throw AcmeError.errorCode(self.status.code, self.status.reasonPhrase)
        }
    }
    
}

public protocol Decoder {
    func decode<T>(_ type: T.Type, from: Data) throws -> T where T : Decodable
}
extension JSONDecoder : Decoder {}
