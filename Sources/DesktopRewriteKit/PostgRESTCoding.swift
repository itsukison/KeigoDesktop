import Foundation

/// Shared PostgREST wire conventions.
///
/// Extracted when a second store needed them: snake_case columns and ISO-8601
/// timestamps with a variable number of fractional-second digits, which `.iso8601`
/// alone rejects. Two copies of that date-decoding fallback would have been two
/// places to get it wrong.
enum PostgRESTCoding {

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: raw) { return date }
            if let date = plain.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Bad timestamp: \(raw)")
            )
        }
        return decoder
    }()

    /// PostgREST accepts plain ISO-8601 for `timestamptz`.
    static func timestamp(_ date: Date) -> String {
        plain.string(from: date)
    }

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
