import XCTest
@testable import Snippy

final class URLCleanerTests: XCTestCase {
    private func assertCleans(_ input: String, to expected: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(URLCleaner.clean(input), expected, file: file, line: line)
    }

    private func assertUnchanged(_ input: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(URLCleaner.clean(input), file: file, line: line)
    }

    // MARK: Generic tracking

    func testStripsUTMButKeepsRealParameters() {
        assertCleans("https://example.com/page?id=5&utm_source=news&utm_medium=email",
                     to: "https://example.com/page?id=5")
    }

    func testDropsQuestionMarkWhenNothingIsLeft() {
        assertCleans("https://example.com/a?utm_source=x", to: "https://example.com/a")
    }

    func testKeepsFragment() {
        assertCleans("https://example.com/docs?fbclid=abc#section-2",
                     to: "https://example.com/docs#section-2")
    }

    func testParameterNamesAreCaseInsensitive() {
        assertCleans("https://example.com/?UTM_Source=a&page=2",
                     to: "https://example.com/?page=2")
    }

    func testPreservesPercentEncoding() {
        assertCleans("https://example.com/search?q=caf%C3%A9&utm_campaign=x",
                     to: "https://example.com/search?q=caf%C3%A9")
    }

    func testTrimsSurroundingWhitespace() {
        assertCleans("  https://example.com/?gclid=1  \n", to: "https://example.com/")
    }

    // MARK: Leaves things alone

    func testCleanURLIsUnchanged() {
        assertUnchanged("https://example.com/page?id=5")
    }

    func testSiteSpecificParamsAreKeptElsewhere() {
        // `ref` is a branch on GitHub, not tracking.
        assertUnchanged("https://github.com/foo/bar/tree/main?ref=abc")
        // `t` is a timestamp on YouTube.
        assertUnchanged("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")
    }

    func testIgnoresTextThatIsNotALoneURL() {
        assertUnchanged("hello world")
        assertUnchanged("Read this https://example.com/?utm_source=x")
        assertUnchanged("mailto:a@b.com?utm_source=x")
    }

    // MARK: Sites

    func testYouTube() {
        assertCleans("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&si=abc123&feature=shared",
                     to: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s")
        assertCleans("https://youtu.be/dQw4w9WgXcQ?si=abc", to: "https://youtu.be/dQw4w9WgXcQ")
    }

    func testTwitter() {
        assertCleans("https://x.com/user/status/123?s=20&t=abcd",
                     to: "https://x.com/user/status/123")
    }

    func testSpotify() {
        assertCleans("https://open.spotify.com/track/abc?si=xyz",
                     to: "https://open.spotify.com/track/abc")
    }

    func testAmazonCollapsesToProductPage() {
        assertCleans("https://www.amazon.com.au/Some-Product-Name/dp/B0ABC12345/ref=sr_1_3?crid=XYZ&keywords=widget&qid=1700000000&sr=8-3",
                     to: "https://www.amazon.com.au/dp/B0ABC12345")
    }

    func testEbayCollapsesToItemPage() {
        assertCleans("https://www.ebay.com.au/itm/Some-Title/123456789012?_trkparms=abc&hash=item1",
                     to: "https://www.ebay.com.au/itm/123456789012")
    }

    func testGoogleSearchKeepsOnlyTheQuery() {
        assertCleans("https://www.google.com/search?q=swift+regex&sca_esv=123&ei=abc&ved=0ah&oq=swift&gs_lp=xyz",
                     to: "https://www.google.com/search?q=swift+regex")
    }

    // MARK: Redirect wrappers

    func testUnwrapsGoogleRedirectAndCleansTarget() {
        assertCleans("https://www.google.com/url?sa=t&url=https%3A%2F%2Fexample.com%2Farticle%3Fid%3D7%26utm_source%3Dgoogle&usg=AOv",
                     to: "https://example.com/article?id=7")
    }

    func testUnwrapsOutlookSafeLinks() {
        assertCleans("https://aus01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fexample.org%2Fpage&data=05%7C01&reserved=0",
                     to: "https://example.org/page")
    }

    func testUnwrapsFacebookRedirect() {
        assertCleans("https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.org%2Fstory%3Ffbclid%3Dxyz&h=AT0",
                     to: "https://example.org/story")
    }
}
