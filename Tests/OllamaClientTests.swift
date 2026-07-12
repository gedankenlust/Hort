import Foundation
import XCTest
@testable import Hort

final class OllamaClientTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFetchModelsReturnsSortedNames() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(#"{"models":[{"name":"zeta"},{"name":"alpha"}]}"#.utf8))
        }

        let models = try await makeClient().fetchModels()
        XCTAssertEqual(models, ["alpha", "zeta"])
    }

    func testFetchModelsReportsOfflineServer() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await makeClient().fetchModels()
            XCTFail("Expected an offline Ollama server to fail")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }

    private func makeClient() -> OllamaClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            session: URLSession(configuration: configuration)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
