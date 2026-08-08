import XCTest
@testable import DesktopRewriteKit

/// `profiles` is shared with the iOS repo (§6), so its row shape is a contract in the
/// same sense `UserPrompt` is.
final class ProfileTests: XCTestCase {

    /// A real PostgREST row: snake_case column, and a timestamp with fractional
    /// seconds — which plain `.iso8601` rejects, and which is the whole reason
    /// `PostgRESTCoding` exists.
    func testDecodesPostgrestRow() throws {
        let json = """
        {
          "id": "6C7A2B5E-7B1F-4E2A-9C3D-1A2B3C4D5E6F",
          "display_name": "孫 逸歓",
          "created_at": "2026-03-14T09:21:44.512841+00:00"
        }
        """
        let profile = try PostgRESTCoding.decoder.decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.displayName, "孫 逸歓")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: profile.createdAt)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 3)
        XCTAssertEqual(parts.day, 14)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 21)
    }

    /// `display_name` is NOT NULL and defaults to `''`, so "no name set" arrives as an
    /// empty string. The account page falls back to the address for exactly this row.
    func testDecodesAnUnnamedProfile() throws {
        let json = """
        {
          "id": "6C7A2B5E-7B1F-4E2A-9C3D-1A2B3C4D5E6F",
          "display_name": "",
          "created_at": "2026-03-14T09:21:44+00:00"
        }
        """
        let profile = try PostgRESTCoding.decoder.decode(Profile.self, from: Data(json.utf8))
        XCTAssertTrue(profile.displayName.isEmpty)
    }
}
