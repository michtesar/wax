import Foundation

enum DatabaseDateCodec {
    private nonisolated(unsafe) static let encoderFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let decoderFormatters: [ISO8601DateFormatter] = [
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }(),
        {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    ]

    private static let sqliteTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    nonisolated static func encode(_ date: Date) -> String {
        encoderFormatter.string(from: date)
    }

    nonisolated static func decode(_ string: String) -> Date? {
        for formatter in decoderFormatters {
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return sqliteTimestampFormatter.date(from: string)
    }
}
