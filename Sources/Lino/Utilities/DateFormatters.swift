import Foundation

enum DateFormatters {
    /// Parses yt-dlp upload_date format (YYYYMMDD)
    static func parseYtDlpDate(_ string: String?) -> Date? {
        guard let string, string.count == 8 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: string)
    }

    /// Formats a date for display in the UI
    static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Formats the addedAt timestamp
    static func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
