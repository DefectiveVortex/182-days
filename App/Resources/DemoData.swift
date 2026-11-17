import Foundation

/// Seeds the in-memory store for `-demo <scenario>` (CI screenshots). Owner: Days 2 — replace freely.
/// Scenarios are whatever Days 2 defines; CI passes them from .github/screenshots.txt.
@MainActor
enum DemoData {
    static func seed(_ store: LogStore, scenario: String) {}
}
