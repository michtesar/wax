import Foundation
import GRDB

struct DatabaseContainer: Sendable {
    let records: any RecordRepository
    let collections: any CollectionRepository
}

enum GRDBRepositoryError: Error {
    case invalidIdentifier(String)
    case invalidDate(String)
}

final class GRDBRecordRepository: RecordRepository, @unchecked Sendable {
    private let databaseManager: GRDBDatabaseManager

    nonisolated init(databaseManager: GRDBDatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchRecords(matching query: RecordListQuery) async throws -> [Record] {
        let request = RecordQueryBuilder.listQuery(for: query)
        return try await databaseManager.read { db in
            try Row.fetchAll(db, sql: request.sql, arguments: request.arguments).map(GRDBRecordRepository.mapRecord)
        }
    }

    func fetchRecord(id: UUID) async throws -> Record? {
        let request = SQLRequest(
            sql: """
            SELECT id, discogs_id, title, artist, year, format, notes, condition, sync_status, created_at, updated_at
            FROM record
            WHERE id = ?
            LIMIT 1
            """,
            arguments: [id.uuidString]
        )

        return try await databaseManager.read { db in
            try Row.fetchOne(db, sql: request.sql, arguments: request.arguments).map(GRDBRecordRepository.mapRecord)
        }
    }

    func fetchRecord(discogsID: Int) async throws -> Record? {
        let request = SQLRequest(
            sql: """
            SELECT id, discogs_id, title, artist, year, format, notes, condition, sync_status, created_at, updated_at
            FROM record
            WHERE discogs_id = ?
            LIMIT 1
            """,
            arguments: [discogsID]
        )

        return try await databaseManager.read { db in
            try Row.fetchOne(db, sql: request.sql, arguments: request.arguments).map(GRDBRecordRepository.mapRecord)
        }
    }

    func upsert(_ record: Record) async throws {
        let request = SQLRequest(
            sql: """
            INSERT INTO record (
                id, discogs_id, title, artist, year, format, notes, condition, sync_status, created_at, updated_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(id) DO UPDATE SET
                discogs_id = excluded.discogs_id,
                title = excluded.title,
                artist = excluded.artist,
                year = excluded.year,
                format = excluded.format,
                notes = excluded.notes,
                condition = excluded.condition,
                sync_status = excluded.sync_status,
                updated_at = excluded.updated_at
            """,
            arguments: [
                record.id.uuidString,
                record.discogsID,
                record.title,
                record.artist,
                record.year,
                record.format,
                record.notes,
                record.condition?.rawValue,
                record.syncStatus.rawValue,
                DatabaseDateCodec.encode(record.createdAt),
                DatabaseDateCodec.encode(record.updatedAt)
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func deleteRecord(id: UUID) async throws {
        let request = SQLRequest(
            sql: "DELETE FROM record WHERE id = ?",
            arguments: [id.uuidString]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func updateNotes(recordID: UUID, notes: String, updatedAt: Date) async throws {
        let request = SQLRequest(
            sql: """
            UPDATE record
            SET notes = ?, sync_status = ?, updated_at = ?
            WHERE id = ?
            """,
            arguments: [
                notes,
                SyncStatus.pending.rawValue,
                DatabaseDateCodec.encode(updatedAt),
                recordID.uuidString
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func updateCondition(recordID: UUID, condition: RecordCondition?, updatedAt: Date) async throws {
        let request = SQLRequest(
            sql: """
            UPDATE record
            SET condition = ?, sync_status = ?, updated_at = ?
            WHERE id = ?
            """,
            arguments: [
                condition?.rawValue,
                SyncStatus.pending.rawValue,
                DatabaseDateCodec.encode(updatedAt),
                recordID.uuidString
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    nonisolated private static func mapRecord(_ row: Row) throws -> Record {
        guard let id = UUID(uuidString: row["id"]) else {
            throw GRDBRepositoryError.invalidIdentifier(row["id"])
        }

        let createdAtString: String = row["created_at"]
        let updatedAtString: String = row["updated_at"]

        guard
            let createdAt = DatabaseDateCodec.decode(createdAtString),
            let updatedAt = DatabaseDateCodec.decode(updatedAtString)
        else {
            throw GRDBRepositoryError.invalidDate("\(createdAtString) | \(updatedAtString)")
        }

        let conditionRaw: String? = row["condition"]
        let syncStatusRaw: String = row["sync_status"]

        return Record(
            id: id,
            discogsID: row["discogs_id"],
            title: row["title"],
            artist: row["artist"],
            year: row["year"],
            format: row["format"],
            notes: row["notes"],
            condition: conditionRaw.flatMap(RecordCondition.init(rawValue:)),
            syncStatus: SyncStatus(rawValue: syncStatusRaw) ?? .failed,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

final class GRDBCollectionRepository: CollectionRepository, @unchecked Sendable {
    private let databaseManager: GRDBDatabaseManager

    nonisolated init(databaseManager: GRDBDatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchEntries(limit: Int, offset: Int) async throws -> [CollectionEntry] {
        let request = SQLRequest(
            sql: """
            SELECT id, record_id, discogs_instance_id, folder_id, date_added, sort_position, sync_status, created_at, updated_at
            FROM collection_entry
            ORDER BY updated_at DESC
            LIMIT ? OFFSET ?
            """,
            arguments: [limit, offset]
        )

        return try await databaseManager.read { db in
            try Row.fetchAll(db, sql: request.sql, arguments: request.arguments).map(GRDBCollectionRepository.mapCollectionEntry)
        }
    }

    func fetchEntry(id: UUID) async throws -> CollectionEntry? {
        let request = SQLRequest(
            sql: """
            SELECT id, record_id, discogs_instance_id, folder_id, date_added, sort_position, sync_status, created_at, updated_at
            FROM collection_entry
            WHERE id = ?
            LIMIT 1
            """,
            arguments: [id.uuidString]
        )

        return try await databaseManager.read { db in
            try Row.fetchOne(db, sql: request.sql, arguments: request.arguments).map(GRDBCollectionRepository.mapCollectionEntry)
        }
    }

    func upsert(_ entry: CollectionEntry) async throws {
        let request = SQLRequest(
            sql: """
            INSERT INTO collection_entry (
                id, record_id, discogs_instance_id, folder_id, date_added, sort_position, sync_status, created_at, updated_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(id) DO UPDATE SET
                record_id = excluded.record_id,
                discogs_instance_id = excluded.discogs_instance_id,
                folder_id = excluded.folder_id,
                date_added = excluded.date_added,
                sort_position = excluded.sort_position,
                sync_status = excluded.sync_status,
                updated_at = excluded.updated_at
            """,
            arguments: [
                entry.id.uuidString,
                entry.recordID.uuidString,
                entry.discogsInstanceID,
                entry.folderID,
                entry.dateAdded.map(DatabaseDateCodec.encode),
                entry.sortPosition,
                entry.syncStatus.rawValue,
                DatabaseDateCodec.encode(entry.createdAt),
                DatabaseDateCodec.encode(entry.updatedAt)
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func deleteEntry(id: UUID) async throws {
        let request = SQLRequest(
            sql: "DELETE FROM collection_entry WHERE id = ?",
            arguments: [id.uuidString]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func markSyncStatus(entryID: UUID, status: SyncStatus, updatedAt: Date) async throws {
        let request = SQLRequest(
            sql: """
            UPDATE collection_entry
            SET sync_status = ?, updated_at = ?
            WHERE id = ?
            """,
            arguments: [
                status.rawValue,
                DatabaseDateCodec.encode(updatedAt),
                entryID.uuidString
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    nonisolated private static func mapCollectionEntry(_ row: Row) throws -> CollectionEntry {
        guard
            let id = UUID(uuidString: row["id"]),
            let recordID = UUID(uuidString: row["record_id"])
        else {
            let entryID: String = row["id"]
            let parentRecordID: String = row["record_id"]
            throw GRDBRepositoryError.invalidIdentifier("\(entryID) | \(parentRecordID)")
        }

        let createdAtString: String = row["created_at"]
        let updatedAtString: String = row["updated_at"]
        let dateAddedString: String? = row["date_added"]

        guard
            let createdAt = DatabaseDateCodec.decode(createdAtString),
            let updatedAt = DatabaseDateCodec.decode(updatedAtString)
        else {
            throw GRDBRepositoryError.invalidDate("\(createdAtString) | \(updatedAtString)")
        }

        return CollectionEntry(
            id: id,
            recordID: recordID,
            discogsInstanceID: row["discogs_instance_id"],
            folderID: row["folder_id"],
            dateAdded: dateAddedString.flatMap(DatabaseDateCodec.decode),
            sortPosition: row["sort_position"],
            syncStatus: SyncStatus(rawValue: row["sync_status"]) ?? .failed,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct SQLRequest: Sendable {
    let sql: String
    let arguments: StatementArguments
}

private enum RecordQueryBuilder {
    nonisolated static func listQuery(for query: RecordListQuery) -> SQLRequest {
        var filters: [String] = []
        var arguments = StatementArguments()

        if let searchText = query.searchText?.trimmingCharacters(in: .whitespacesAndNewlines), !searchText.isEmpty {
            filters.append("(title LIKE ? OR artist LIKE ?)")
            let pattern = "%\(searchText)%"
            arguments += [pattern, pattern]
        }

        if !query.syncStatuses.isEmpty {
            let placeholders = Array(repeating: "?", count: query.syncStatuses.count).joined(separator: ", ")
            filters.append("sync_status IN (\(placeholders))")
            for value in query.syncStatuses.map(\.rawValue).sorted() {
                arguments += [value]
            }
        }

        let whereClause = filters.isEmpty ? "" : "WHERE " + filters.joined(separator: " AND ")
        let sql = """
        SELECT id, discogs_id, title, artist, year, format, notes, condition, sync_status, created_at, updated_at
        FROM record
        \(whereClause)
        ORDER BY updated_at DESC
        LIMIT ? OFFSET ?
        """

        arguments += [query.limit, query.offset]
        return SQLRequest(sql: sql, arguments: arguments)
    }
}
