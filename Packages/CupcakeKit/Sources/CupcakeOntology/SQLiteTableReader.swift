import Foundation
import SQLite3

enum SQLiteTableReader {
    static func readRows(from fileURL: URL, table: String, handleRow: (_ row: [String: String?]) -> Void) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(db)
            throw SQLiteReaderError.openFailed(message)
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
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
