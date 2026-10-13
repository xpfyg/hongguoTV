import XCTest
@testable import HongguoTV

/// 业务层离线测试：mock URLSession（URLProtocol），覆盖
/// 榜单 data-fn-args 解析、首页分区解析、清晰度选择策略、qualityNumber。
final class ContentRepositoryTests: XCTestCase {

    // MARK: - mock HTTP

    private final class MockURLProtocol: URLProtocol {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = MockURLProtocol.handler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (resp, data) = try handler(request)
                client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    private func repo(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data)) -> ContentRepository {
        MockURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return ContentRepository(session: URLSession(configuration: config), clock: { 0 })
    }

    private func ok(_ request: URLRequest, _ body: String) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }

    // MARK: - 清晰度选择

    private func streamRepo(_ variants: [(Int, String, String)]) -> ContentRepository {
        repo { request in
            if request.url?.host == "example.com" {
                var rows: [String: [String: Any]] = [:]
                for (i, v) in variants.enumerated() {
                    rows["video_\(i)"] = ["vheight": v.0, "codec_type": v.1, "main_url": v.2]
                }
                let payload: [String: Any] = ["video_info": ["data": ["video_list": rows]]]
                let data = try! JSONSerialization.data(withJSONObject: payload)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            } else {
                let payload: [String: Any] = ["data": ["123": ["video_model": ["fallback_api": "https://example.com/stream"]]]]
                let data = try! JSONSerialization.data(withJSONObject: payload)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }
        }
    }

    func testIncompatibleByteVc2DoesNotBecomeAudioOnlyPlayback() async throws {
        let repo = streamRepo([(720, "bytevc2", "https://example.com/unsupported"), (1080, "bytevc1", "https://example.com/hevc")])
        let result = try await repo.stream(id: "123", maxQuality: 720)
        XCTAssertEqual(result.url, "https://example.com/hevc")
        XCTAssertEqual(result.quality, "1080P（兼容资源）")
    }

    func testCompatibleLowerQualityWinsBeforeHigherResolutionFallback() async throws {
        let repo = streamRepo([(720, "bytevc2", "https://example.com/unsupported"), (480, "h264", "https://example.com/avc"), (1080, "bytevc1", "https://example.com/hevc")])
        let result = try await repo.stream(id: "123", maxQuality: 720)
        XCTAssertEqual(result.quality, "480P")
    }

    func testEntirelyIncompatibleSourceFailsBeforeStartingAudio() async throws {
        let repo = streamRepo([(720, "ByteVC2", "https://example.com/unsupported"), (480, "bvc2", "https://example.com/unsupported2")])
        do {
            _ = try await repo.stream(id: "123", maxQuality: 720)
            XCTFail("应抛出错误")
        } catch { /* 期望失败 */ }
    }

    func testLegacyMissingCodecLabelKeepsQualityLimit() async throws {
        let repo = streamRepo([(720, "", "https://example.com/legacy"), (1080, "bytevc1", "https://example.com/hevc")])
        let result = try await repo.stream(id: "123", maxQuality: 720)
        XCTAssertEqual(result.quality, "720P")
    }

    // MARK: - 首页 / 榜单解析

    private func script(_ name: String, _ args: String) -> String {
        "<script data-fn-name=\"\(name)\" data-fn-args=\"\(args)\"></script>"
    }

    private func currentRank(_ payload: [String: Any]) -> String {
        let payloadJSON = try! String(data: JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!
        let args: [Any] = [
            "rank_hot-comic-drama/page",
            [["key": "content", "routerDataFnName": "p", "routerDataFnArgs": [payloadJSON]]],
        ]
        let argsJSON = try! String(data: JSONSerialization.data(withJSONObject: args), encoding: .utf8)!
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        return script("mergeLoaderData", argsJSON)
    }

    func testRankPageParsesDataFnArgsPayload() async throws {
        let payload: [String: Any] = [
            "isSuccess": true,
            "rankList": [[
                "seriesId": "123", "title": "测试漫剧",
                "cover": "https:\\u002F\\u002Fexample.com\\u002Fcover.jpg",
                "episodeCount": 12, "tags": ["玄幻"],
            ]],
        ]
        let html = "<script>_ROUTER_DATA={};</script>" + currentRank(payload)
        let repo = repo { request in self.ok(request, html) }
        let items = try await repo.rankPage(route: "hot-comic-drama", page: 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "123")
        XCTAssertEqual(items[0].title, "测试漫剧")
        XCTAssertEqual(items[0].cover, "https://example.com/cover.jpg")
        XCTAssertEqual(items[0].badge, "全 12 集")
        XCTAssertEqual(items[0].tags, "玄幻")
    }

    func testRankPageRejectsShellPageWithoutPayload() async throws {
        let repo = repo { request in self.ok(request, "<html><body>empty</body></html>") }
        do {
            _ = try await repo.rankPage(route: "hot-drama", page: 1)
            XCTFail("壳页面应解析失败")
        } catch { /* 期望失败 */ }
    }

    func testHomeParsesAllSection() async throws {
        let html = "<script>_ROUTER_DATA={\"loaderData\":{\"page\":{\"homeSections\":[{\"tab_type\":\"all\",\"video_list\":[{\"video_data\":{\"series_id\":\"1\",\"series_name\":\"测试短剧\",\"series_cover\":\"\\u002F\\u002Fexample.com\\u002Fa.jpg\",\"episode_cnt\":5,\"tags\":[{\"name\":\"爽剧\"}]}}]}]}}};</script>"
        let repo = repo { request in self.ok(request, html) }
        let page = try await repo.home(page: 1)
        XCTAssertEqual(page.items.count, 1)
        XCTAssertEqual(page.items[0].id, "1")
        XCTAssertEqual(page.items[0].badge, "全 5 集")
        XCTAssertEqual(page.items[0].tags, "爽剧")
        XCTAssertTrue(page.hasMore)
    }

    // MARK: - 工具

    func testQualityNumber() {
        XCTAssertEqual(ContentRepository.qualityNumber("1080P"), 1080)
        XCTAssertEqual(ContentRepository.qualityNumber("720P高清"), 720)
        XCTAssertEqual(ContentRepository.qualityNumber("1920"), 1080)
        XCTAssertEqual(ContentRepository.qualityNumber("854"), 480)
        XCTAssertEqual(ContentRepository.qualityNumber("whatever"), 0)
    }

    func testCleanUrl() {
        XCTAssertEqual(ContentRepository.cleanUrl("https:\\/\\/a.com\\u002Fb&amp;c"), "https://a.com/b&c")
    }

    func testDecodeHtml() {
        XCTAssertEqual(ContentRepository.decodeHtml("&quot;a&#x2F;b&#39;&amp;&lt;&gt;"), "\"a/b'&<>")
    }
}
