import Foundation
import SwiftData

/// One Session per Study Day. The one-per-day rule is kept by
/// `StudyStore.dedupeSessions()`, using `updatedAt` (later wins).
///
/// Every property is defaulted and there is no unique constraint: a merge can
/// legitimately produce two records for the same day for a moment, and the
/// dedupe resolves it rather than the store refusing the write.
@Model
final class StudySession {
    var date: Date = Date.distantPast   // normalized to midnight (start of day)
    var duration: TimeInterval = 0      // total seconds studied that day
    var isManualEdit: Bool = false      // true if user manually edited this entry
    /// When this record was last written. Resolves duplicates after a merge.
    var updatedAt: Date = Date.distantPast
    /// True until the row has reached the Account's server copy. Locally
    /// created Sessions start true; the sync layer clears it.
    var needsUpload: Bool = true

    init(date: Date, duration: TimeInterval, isManualEdit: Bool = false) {
        self.date = Calendar.current.startOfDay(for: date)
        self.duration = duration
        self.isManualEdit = isManualEdit
        self.updatedAt = Date()
    }
}

extension StudySession {
    /// Formats duration as "Xh Ym" for display
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
