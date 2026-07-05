import Foundation
import SQLite3

/// Reads every row of a single named table out of a plain, read-only SQLite file — no ORM, no
/// external dependency, just the system `libsqlite3` C API that ships with iOS/macOS (`import
/// SQLite3` resolves to it directly, no extra linking needed for an app target; this library
/// target declares it explicitly in `Package.swift` since SwiftPM library builds don't always
/// inherit the app's default link set). Verified end to end against a real downloaded and
/// gzip-decompressed ontology table file.
///
/// Every exported ontology/column-template/schema table is text-only or JSON-as-text
/// (`export_mobile_snapshot.py`'s `_scalar_fields` serializes `JSONField`s to JSON strings), so
/// this only ever reads columns as strings — callers parse further (e.g. JSON-decoding a
/// `TEXT` column) as needed.
enum SQLiteTableReader {
    /// Calls `handleRow` once per row, with a dictionary of column name -> string value (`nil`
    /// for a SQL `NULL`, not an empty string — the two are meaningfully different for optional
    /// fields like `Tissue.accession`).
    static func readRows(from fileURL: URL, table: String, handleRow: (_ row: [String: String?]) -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw SQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        // Table names in these exports are always the trusted `type_key`/dataset name from our
        // own manifest, never external input — safe to interpolate directly into the query.
        guard sqlite3_prepare_v2(db, "SELECT * FROM \"\(table)\"", -1, &statement, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(db))
            throw SQLiteReaderError.prepareFailed(message)
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = sqlite3_column_count(statement)
        let columnNames = (0..<columnCount).map { String(cString: sqlite3_column_name(statement, $0)) }

        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String?] = [:]
            for index in 0..<columnCount {
                if sqlite3_column_type(statement, index) == SQLITE_NULL {
                    row[columnNames[Int(index)]] = String?.none
                } else if let cString = sqlite3_column_text(statement, index) {
                    row[columnNames[Int(index)]] = String(cString: cString)
                }
            }
            handleRow(row)
        }
    }
}

enum SQLiteReaderError: Error {
    case openFailed(String)
    case prepareFailed(String)
}
