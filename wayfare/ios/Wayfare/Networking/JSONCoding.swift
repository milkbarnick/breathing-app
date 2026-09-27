import Foundation

/// JSON coders configured for the contract: camelCase keys (Swift names already match),
/// ISO-8601 UTC instants without fractional seconds.
enum JSONCoding {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // `.iso8601` writes "2026-10-01T14:30:00Z" (UTC, no fractional seconds), exactly as the contract wants.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        // The contract sends no fractional seconds, which `.iso8601` handles. We also accept a
        // fractional form ("...:00.000Z"), which a JavaScript `toISOString()` would produce, so one
        // server slip can't break sync.
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = JSONCoding.parseInstant(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Expected an ISO-8601 instant, got \(text)")
            }
            return date
        }
        return decoder
    }

    /// Parses "2026-10-01T14:30:00Z" or "2026-10-01T14:30:00.000Z".
    static func parseInstant(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// "2026-10-01T14:30:00Z".
    static func formatInstant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
