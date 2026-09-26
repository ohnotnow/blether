import XCTest
@testable import Blether

final class StreamPlaylistTests: XCTestCase {
    private let base = URL(string: "http://example.com/radio/station.pls")!

    // Shaped like SomaFM's dubstep.pls, fetched 2026-09-26.
    private let pls = """
    [playlist]
    numberofentries=3
    File2=http://ice6.example.com/dubstep-128-mp3
    Title2=Mirror two
    Length2=-1
    File1=http://ice2.example.com/dubstep-128-mp3
    Title1=Mirror one
    Length1=-1
    File3=http://ice4.example.com/dubstep-128-mp3
    Version=2
    """

    func testPlsGivesItsFilesInNumberOrder() {
        XCTAssertEqual(StreamPlaylist.entries(in: pls, base: base).map(\.absoluteString), [
            "http://ice2.example.com/dubstep-128-mp3",
            "http://ice6.example.com/dubstep-128-mp3",
            "http://ice4.example.com/dubstep-128-mp3",
        ])
    }

    func testPlainM3UGivesItsLines() {
        let body = "http://stream.example.com:80/GSW.mp3\n"
        XCTAssertEqual(StreamPlaylist.entries(in: body, base: base).map(\.absoluteString), ["http://stream.example.com:80/GSW.mp3"])
    }

    func testExtendedM3USkipsCommentsAndBlankLines() {
        let body = "#EXTM3U\r\n\r\n#EXTINF:-1,Station\r\nhttp://a.example.com/live\r\n#EXTINF:-1,Other\r\nhttp://b.example.com/live.pls\r\n"
        XCTAssertEqual(StreamPlaylist.entries(in: body, base: base).map(\.absoluteString), ["http://a.example.com/live", "http://b.example.com/live.pls"])
    }

    func testRelativeEntriesResolveAgainstThePlaylist() {
        XCTAssertEqual(StreamPlaylist.entries(in: "live.mp3", base: base).map(\.absoluteString), ["http://example.com/radio/live.mp3"])
    }

    func testDirectAndHLSURLsAreNotFetched() async throws {
        for string in ["http://example.com/stream", "http://example.com/live.mp3", "https://example.com/live/index.m3u8"] {
            let url = URL(string: string)!
            let urls = try await StreamPlaylist.resolve(url) { _ in XCTFail("fetched \(string)"); return Data() }
            XCTAssertEqual(urls, [url])
        }
    }

    func testPlaylistIsFetchedOnceAndNestedPlaylistsAreNotFollowed() async throws {
        var fetched: [URL] = []
        let url = URL(string: "http://example.com/list.M3U")!
        let urls = try await StreamPlaylist.resolve(url) { url in
            fetched.append(url)
            return Data("http://a.example.com/one.pls\nhttp://b.example.com/two\n".utf8)
        }
        XCTAssertEqual(fetched, [url])
        XCTAssertEqual(urls.map(\.absoluteString), ["http://a.example.com/one.pls", "http://b.example.com/two"])
    }

    func testPlaylistWithNoEntriesThrows() async {
        do {
            _ = try await StreamPlaylist.resolve(base) { _ in Data("[playlist]\nnumberofentries=0\n".utf8) }
            XCTFail("expected a throw")
        } catch {
            XCTAssertTrue(error is StreamPlaylistError)
        }
    }
}
