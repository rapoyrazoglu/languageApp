import XCTest
@testable import PaktlyKit

final class RegistryClientTests: XCTestCase {
    private let baseURL = URL(string: "https://api.test")!

    override func tearDown() {
        StubURLProtocol.uninstall()
        super.tearDown()
    }

    private func makeClient(token: String? = nil) -> RegistryClient {
        RegistryClient(baseURL: baseURL, session: StubURLProtocol.session(), token: token)
    }

    // MARK: - Pack list

    func testListPacks_DecodesPageAndForwardsQueryParams() async throws {
        let json = """
        {
          "packs": [
            {
              "id": "com.example.ja",
              "name": "Japanese A1",
              "languageCode": "ja",
              "languageName": "Japanese",
              "level": "A1",
              "authorName": "Ata",
              "license": "CC-BY-4.0",
              "tags": ["beginner"],
              "latestVersion": "0.2.0"
            }
          ],
          "nextCursor": "abc==",
          "limit": 50
        }
        """
        StubURLProtocol.install { request in
            StubURLProtocol.ok(request, json: json)
        }

        let client = makeClient()
        let page = try await client.listPacks(language: "ja", level: "A1", tag: "beginner", q: "hira", limit: 50)

        XCTAssertEqual(page.packs.count, 1)
        XCTAssertEqual(page.packs[0].id, "com.example.ja")
        XCTAssertEqual(page.packs[0].languageCode, "ja")
        XCTAssertEqual(page.nextCursor, "abc==")
        XCTAssertEqual(page.limit, 50)

        let captured = try XCTUnwrap(StubURLProtocol.capturedRequests().first)
        let url = try XCTUnwrap(captured.url)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["language"], "ja")
        XCTAssertEqual(items["level"], "A1")
        XCTAssertEqual(items["tag"], "beginner")
        XCTAssertEqual(items["q"], "hira")
        XCTAssertEqual(items["limit"], "50")
        XCTAssertEqual(captured.httpMethod, "GET")
    }

    func testListPacks_OmitsAbsentFilters() async throws {
        StubURLProtocol.install { request in
            StubURLProtocol.ok(request, json: #"{"packs": [], "limit": 50}"#)
        }
        let client = makeClient()
        _ = try await client.listPacks()

        let captured = try XCTUnwrap(StubURLProtocol.capturedRequests().first)
        // No query string at all when the caller passes no filters.
        XCTAssertNil(URLComponents(url: captured.url!, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - Pack detail + download

    func testGetPack_DecodesPackAndVersions() async throws {
        let json = """
        {
          "pack": {
            "id": "com.example.ja",
            "name": "Japanese A1",
            "languageCode": "ja",
            "languageName": "Japanese",
            "authorName": "Ata",
            "license": "CC-BY-4.0",
            "createdAt": "2026-05-05T17:21:59.123Z"
          },
          "versions": [
            {
              "packId": "com.example.ja",
              "version": "0.2.0",
              "schemaVersion": "1.1.0",
              "sha256": "abc",
              "sizeBytes": 12345,
              "source": "github",
              "createdAt": "2026-05-05T17:21:59Z"
            }
          ]
        }
        """
        StubURLProtocol.install { req in StubURLProtocol.ok(req, json: json) }

        let client = makeClient()
        let detail = try await client.getPack(id: "com.example.ja")

        XCTAssertEqual(detail.pack.id, "com.example.ja")
        XCTAssertNotNil(detail.pack.createdAt)
        XCTAssertEqual(detail.versions.count, 1)
        XCTAssertEqual(detail.versions[0].source, .github)
        XCTAssertEqual(detail.versions[0].sizeBytes, 12345)
    }

    func testDownloadInfo_Decodes() async throws {
        let json = """
        {
          "url": "https://s3.example/pack.zip?sig=...",
          "sha256": "deadbeef",
          "sizeBytes": 4096,
          "expiresIn": 600
        }
        """
        StubURLProtocol.install { req in StubURLProtocol.ok(req, json: json) }
        let client = makeClient()
        let info = try await client.downloadInfo(packId: "com.example.ja", version: "0.2.0")
        XCTAssertEqual(info.sha256, "deadbeef")
        XCTAssertEqual(info.expiresIn, 600)
        XCTAssertEqual(info.sizeBytes, 4096)
    }

    // MARK: - Auth

    func testLogin_StoresTokenAndSendsBearerOnSubsequentCalls() async throws {
        let tokenJSON = """
        {
          "token": "jwt-abc",
          "expiresAt": "2026-06-05T00:00:00Z",
          "user": { "id": "u1", "email": "a@b.com" }
        }
        """
        let meJSON = #"{"id":"u1","email":"a@b.com"}"#

        StubURLProtocol.install { req in
            if req.url?.path == "/v1/auth/login" {
                return StubURLProtocol.ok(req, json: tokenJSON)
            }
            return StubURLProtocol.ok(req, json: meJSON)
        }

        let client = makeClient()
        let login = try await client.login(email: "a@b.com", password: "correct horse battery staple")
        XCTAssertEqual(login.token, "jwt-abc")
        XCTAssertEqual(login.user.id, "u1")

        // Token must persist into the next call.
        let storedToken = await client.currentToken()
        XCTAssertEqual(storedToken, "jwt-abc")

        _ = try await client.me()

        let requests = StubURLProtocol.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Authorization"))  // login is unauthenticated
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer jwt-abc")
    }

    func testRegister_PostsJSONBody() async throws {
        let tokenJSON = """
        {
          "token": "tok",
          "expiresAt": "2026-06-05T00:00:00Z",
          "user": { "id": "u1", "email": "a@b.com" }
        }
        """
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 201, json: tokenJSON) }

        let client = makeClient()
        _ = try await client.register(email: "a@b.com", password: "correct horse battery staple", displayName: "Ata")

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests().first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        // URLProtocol strips httpBody on iOS/macOS — read via httpBodyStream.
        let body = readBody(req)
        let decoded = try JSONDecoder().decode(RegisterRequest.self, from: body)
        XCTAssertEqual(decoded.email, "a@b.com")
        XCTAssertEqual(decoded.displayName, "Ata")
    }

    // MARK: - Authoring

    func testUploadPack_PostsMultipartWithZipBytesAndBearerAuth() async throws {
        let resultJSON = """
        {"packId":"com.example.ja","version":"0.2.0","sha256":"abc","sizeBytes":4096}
        """
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 201, json: resultJSON) }

        let client = makeClient(token: "tok")
        let zip = Data((0..<256).map { UInt8($0 & 0xff) })
        let result = try await client.uploadPack(zipData: zip, filename: "example-nihongo.zip")
        XCTAssertEqual(result.packId, "com.example.ja")
        XCTAssertEqual(result.sizeBytes, 4096)

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests().first)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url?.path, "/v1/packs/upload")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")

        let contentType = try XCTUnwrap(req.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="), "unexpected: \(contentType)")
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))

        let body = readBody(req)
        let bodyString = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(bodyString.contains("--\(boundary)"), "missing boundary marker")
        XCTAssertTrue(bodyString.contains(#"name="pack""#), "missing form field name")
        XCTAssertTrue(bodyString.contains(#"filename="example-nihongo.zip""#), "missing filename")
        XCTAssertTrue(bodyString.contains("Content-Type: application/zip"), "missing part content-type")
        // Zip bytes must round-trip through the multipart frame intact.
        XCTAssertTrue(body.range(of: zip) != nil, "zip payload missing or altered")
    }

    func testImportGitHub_PostsRepoURL() async throws {
        let resultJSON = """
        {"packId":"com.example.ja","version":"0.3.0","sha256":"def","sizeBytes":8192}
        """
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 201, json: resultJSON) }

        let client = makeClient(token: "tok")
        let result = try await client.importGitHub(repoUrl: "https://github.com/ata/example-nihongo")
        XCTAssertEqual(result.version, "0.3.0")

        let req = try XCTUnwrap(StubURLProtocol.capturedRequests().first)
        XCTAssertEqual(req.url?.path, "/v1/packs/import-github")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        let body = readBody(req)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["repoUrl"], "https://github.com/ata/example-nihongo")
    }

    // MARK: - Errors

    func testStructured401_MapsToHTTPErrorWithCode() async throws {
        let body = #"{"error":{"code":"UNAUTHORIZED","message":"missing token"}}"#
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 401, json: body) }

        let client = makeClient(token: "expired")
        do {
            _ = try await client.me()
            XCTFail("expected error")
        } catch let RegistryError.http(status, code, message, fields, retryAfter) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(code, .unauthorized)
            XCTAssertEqual(message, "missing token")
            XCTAssertEqual(fields, [])
            XCTAssertNil(retryAfter)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testValidationError_PreservesFields() async throws {
        let body = """
        {
          "error": {
            "code": "PACK_VALIDATION_FAILED",
            "message": "manifest invalid",
            "fields": [
              { "path": "manifest.json#/id", "message": "must be reverse-DNS" },
              { "path": "lessons/001.json#/blocks/0", "message": "unknown block type" }
            ]
          }
        }
        """
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 422, json: body) }

        let client = makeClient(token: "tok")
        do {
            _ = try await client.getPack(id: "x")
            XCTFail("expected error")
        } catch let RegistryError.http(status, code, _, fields, _) {
            XCTAssertEqual(status, 422)
            XCTAssertEqual(code, .packValidationFailed)
            XCTAssertEqual(fields.count, 2)
            XCTAssertEqual(fields[0].path, "manifest.json#/id")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRateLimit_SurfacesRetryAfter() async throws {
        let body = #"{"error":{"code":"RATE_LIMITED","message":"slow down"}}"#
        StubURLProtocol.install { req in
            StubURLProtocol.response(req, status: 429, json: body, headers: ["Retry-After": "30"])
        }
        let client = makeClient()
        do {
            _ = try await client.listPacks()
            XCTFail("expected error")
        } catch let RegistryError.http(status, code, _, _, retryAfter) {
            XCTAssertEqual(status, 429)
            XCTAssertEqual(code, .rateLimited)
            XCTAssertEqual(retryAfter, 30)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testUnknownErrorCode_MapsToUnknown() async throws {
        let body = #"{"error":{"code":"BRAND_NEW_CODE","message":"future"}}"#
        StubURLProtocol.install { req in StubURLProtocol.response(req, status: 418, json: body) }
        let client = makeClient()
        do {
            _ = try await client.listPacks()
            XCTFail("expected error")
        } catch let RegistryError.http(_, code, _, _, _) {
            XCTAssertEqual(code, .unknown)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testNonJSONErrorBody_MapsToUnexpectedResponse() async throws {
        StubURLProtocol.install { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (resp, Data("Bad Gateway (HTML page)".utf8))
        }
        let client = makeClient()
        do {
            _ = try await client.listPacks()
            XCTFail("expected error")
        } catch let RegistryError.unexpectedResponse(status, body) {
            XCTAssertEqual(status, 502)
            XCTAssertTrue(body.contains("Bad Gateway"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

// MARK: - Helpers

private func readBody(_ request: URLRequest) -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 1024
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}
