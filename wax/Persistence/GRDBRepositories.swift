import Foundation
import GRDB

struct DatabaseContainer: Sendable {
    let records: any RecordRepository
    let collections: any CollectionRepository
    let syncOperations: any SyncOperationRepository
    let syncCheckpoints: any SyncCheckpointRepository
    let imageAssets: any ImageAssetRepository

    init(databaseManager: GRDBDatabaseManager) {
        self.records = GRDBRecordRepository(databaseManager: databaseManager)
        self.collections = GRDBCollectionRepository(databaseManager: databaseManager)
        self.syncOperations = GRDBSyncOperationRepository(databaseManager: databaseManager)
        self.syncCheckpoints = GRDBSyncCheckpointRepository(databaseManager: databaseManager)
        self.imageAssets = GRDBImageAssetRepository(databaseManager: databaseManager)
    }
}

enum GRDBRepositoryError: Error {
    case invalidIdentifier(String)
    case invalidDate(String)
    case invalidURL(String)
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

final class GRDBSyncOperationRepository: SyncOperationRepository, @unchecked Sendable {
    private let databaseManager: GRDBDatabaseManager

    nonisolated init(databaseManager: GRDBDatabaseManager) {
        self.databaseManager = databaseManager
    }

    func enqueue(_ operation: SyncOperation) async throws {
        let request = SQLRequest(
            sql: """
            INSERT INTO sync_operation (
                id, entity_type, entity_id, operation_type, payload, state, attempt_count, next_attempt_at,
                last_error_message, created_at, updated_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(id) DO UPDATE SET
                entity_type = excluded.entity_type,
                entity_id = excluded.entity_id,
                operation_type = excluded.operation_type,
                payload = excluded.payload,
                state = excluded.state,
                attempt_count = excluded.attempt_count,
                next_attempt_at = excluded.next_attempt_at,
                last_error_message = excluded.last_error_message,
                updated_at = excluded.updated_at
            """,
            arguments: [
                operation.id.uuidString,
                operation.entityType.rawValue,
                operation.entityID.uuidString,
                operation.operationType.rawValue,
                operation.payload,
                operation.state.rawValue,
                operation.attemptCount,
                operation.nextAttemptAt.map(DatabaseDateCodec.encode),
                operation.lastErrorMessage,
                DatabaseDateCodec.encode(operation.createdAt),
                DatabaseDateCodec.encode(operation.updatedAt)
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func fetchPendingOperations(limit: Int, asOf date: Date) async throws -> [SyncOperation] {
        let request = SQLRequest(
            sql: """
            SELECT id, entity_type, entity_id, operation_type, payload, state, attempt_count, next_attempt_at,
                   last_error_message, created_at, updated_at
            FROM sync_operation
            WHERE state IN (?, ?)
              AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
            ORDER BY created_at ASC
            LIMIT ?
            """,
            arguments: [
                SyncOperationState.pending.rawValue,
                SyncOperationState.failed.rawValue,
                DatabaseDateCodec.encode(date),
                limit
            ]
        )

        return try await databaseManager.read { db in
            try Row.fetchAll(db, sql: request.sql, arguments: request.arguments).map(GRDBSyncOperationRepository.mapSyncOperation)
        }
    }

    func update(_ operation: SyncOperation) async throws {
        try await enqueue(operation)
    }

    func deleteOperation(id: UUID) async throws {
        let request = SQLRequest(
            sql: "DELETE FROM sync_operation WHERE id = ?",
            arguments: [id.uuidString]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    nonisolated private static func mapSyncOperation(_ row: Row) throws -> SyncOperation {
        guard
            let id = UUID(uuidString: row["id"]),
            let entityID = UUID(uuidString: row["entity_id"])
        else {
            let value: String = row["id"]
            let entityValue: String = row["entity_id"]
            throw GRDBRepositoryError.invalidIdentifier("\(value) | \(entityValue)")
        }

        let createdAtString: String = row["created_at"]
        let updatedAtString: String = row["updated_at"]
        let nextAttemptAtString: String? = row["next_attempt_at"]

        guard
            let createdAt = DatabaseDateCodec.decode(createdAtString),
            let updatedAt = DatabaseDateCodec.decode(updatedAtString)
        else {
            throw GRDBRepositoryError.invalidDate("\(createdAtString) | \(updatedAtString)")
        }

        return SyncOperation(
            id: id,
            entityType: SyncEntityType(rawValue: row["entity_type"]) ?? .record,
            entityID: entityID,
            operationType: SyncOperationType(rawValue: row["operation_type"]) ?? .update,
            payload: row["payload"],
            state: SyncOperationState(rawValue: row["state"]) ?? .failed,
            attemptCount: row["attempt_count"],
            nextAttemptAt: nextAttemptAtString.flatMap(DatabaseDateCodec.decode),
            lastErrorMessage: row["last_error_message"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

final class GRDBSyncCheckpointRepository: SyncCheckpointRepository, @unchecked Sendable {
    private let databaseManager: GRDBDatabaseManager

    nonisolated init(databaseManager: GRDBDatabaseManager) {
        self.databaseManager = databaseManager
    }

    func checkpoint(for scope: SyncScope) async throws -> SyncCheckpoint? {
        let request = SQLRequest(
            sql: """
            SELECT id, scope, cursor, last_synced_at, created_at, updated_at
            FROM sync_checkpoint
            WHERE scope = ?
            LIMIT 1
            """,
            arguments: [scope.rawValue]
        )

        return try await databaseManager.read { db in
            try Row.fetchOne(db, sql: request.sql, arguments: request.arguments).map(GRDBSyncCheckpointRepository.mapCheckpoint)
        }
    }

    func save(_ checkpoint: SyncCheckpoint) async throws {
        let request = SQLRequest(
            sql: """
            INSERT INTO sync_checkpoint (
                id, scope, cursor, last_synced_at, created_at, updated_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(scope) DO UPDATE SET
                id = excluded.id,
                cursor = excluded.cursor,
                last_synced_at = excluded.last_synced_at,
                updated_at = excluded.updated_at
            """,
            arguments: [
                checkpoint.id.uuidString,
                checkpoint.scope.rawValue,
                checkpoint.cursor,
                checkpoint.lastSyncedAt.map(DatabaseDateCodec.encode),
                DatabaseDateCodec.encode(checkpoint.createdAt),
                DatabaseDateCodec.encode(checkpoint.updatedAt)
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    nonisolated private static func mapCheckpoint(_ row: Row) throws -> SyncCheckpoint {
        guard let id = UUID(uuidString: row["id"]) else {
            let value: String = row["id"]
            throw GRDBRepositoryError.invalidIdentifier(value)
        }

        let createdAtString: String = row["created_at"]
        let updatedAtString: String = row["updated_at"]
        let lastSyncedAtString: String? = row["last_synced_at"]

        guard
            let createdAt = DatabaseDateCodec.decode(createdAtString),
            let updatedAt = DatabaseDateCodec.decode(updatedAtString)
        else {
            throw GRDBRepositoryError.invalidDate("\(createdAtString) | \(updatedAtString)")
        }

        return SyncCheckpoint(
            id: id,
            scope: SyncScope(rawValue: row["scope"]) ?? .collectionDelta,
            cursor: row["cursor"],
            lastSyncedAt: lastSyncedAtString.flatMap(DatabaseDateCodec.decode),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

final class GRDBImageAssetRepository: ImageAssetRepository, @unchecked Sendable {
    private let databaseManager: GRDBDatabaseManager

    nonisolated init(databaseManager: GRDBDatabaseManager) {
        self.databaseManager = databaseManager
    }

    func fetchImageAsset(recordID: UUID) async throws -> ImageAsset? {
        let request = SQLRequest(
            sql: """
            SELECT id, record_id, discogs_image_url, thumbnail_local_path, fullsize_local_path, pixel_width,
                   pixel_height, byte_size, last_accessed_at, created_at, updated_at
            FROM image_asset
            WHERE record_id = ?
            LIMIT 1
            """,
            arguments: [recordID.uuidString]
        )

        return try await databaseManager.read { db in
            try Row.fetchOne(db, sql: request.sql, arguments: request.arguments).map(GRDBImageAssetRepository.mapImageAsset)
        }
    }

    func upsert(_ asset: ImageAsset) async throws {
        let request = SQLRequest(
            sql: """
            INSERT INTO image_asset (
                id, record_id, discogs_image_url, thumbnail_local_path, fullsize_local_path, pixel_width,
                pixel_height, byte_size, last_accessed_at, created_at, updated_at
            ) VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(id) DO UPDATE SET
                record_id = excluded.record_id,
                discogs_image_url = excluded.discogs_image_url,
                thumbnail_local_path = excluded.thumbnail_local_path,
                fullsize_local_path = excluded.fullsize_local_path,
                pixel_width = excluded.pixel_width,
                pixel_height = excluded.pixel_height,
                byte_size = excluded.byte_size,
                last_accessed_at = excluded.last_accessed_at,
                updated_at = excluded.updated_at
            """,
            arguments: [
                asset.id.uuidString,
                asset.recordID.uuidString,
                asset.discogsImageURL?.absoluteString,
                asset.thumbnailLocalPath,
                asset.fullsizeLocalPath,
                asset.pixelWidth,
                asset.pixelHeight,
                asset.byteSize,
                asset.lastAccessedAt.map(DatabaseDateCodec.encode),
                DatabaseDateCodec.encode(asset.createdAt),
                DatabaseDateCodec.encode(asset.updatedAt)
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func markAccess(recordID: UUID, at date: Date) async throws {
        let request = SQLRequest(
            sql: """
            UPDATE image_asset
            SET last_accessed_at = ?, updated_at = ?
            WHERE record_id = ?
            """,
            arguments: [
                DatabaseDateCodec.encode(date),
                DatabaseDateCodec.encode(date),
                recordID.uuidString
            ]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    func deleteImageAsset(id: UUID) async throws {
        let request = SQLRequest(
            sql: "DELETE FROM image_asset WHERE id = ?",
            arguments: [id.uuidString]
        )

        _ = try await databaseManager.write { db in
            try db.execute(sql: request.sql, arguments: request.arguments)
        }
    }

    nonisolated private static func mapImageAsset(_ row: Row) throws -> ImageAsset {
        guard
            let id = UUID(uuidString: row["id"]),
            let recordID = UUID(uuidString: row["record_id"])
        else {
            let value: String = row["id"]
            let recordValue: String = row["record_id"]
            throw GRDBRepositoryError.invalidIdentifier("\(value) | \(recordValue)")
        }

        let createdAtString: String = row["created_at"]
        let updatedAtString: String = row["updated_at"]
        let lastAccessedAtString: String? = row["last_accessed_at"]
        let discogsImageURLString: String? = row["discogs_image_url"]

        guard
            let createdAt = DatabaseDateCodec.decode(createdAtString),
            let updatedAt = DatabaseDateCodec.decode(updatedAtString)
        else {
            throw GRDBRepositoryError.invalidDate("\(createdAtString) | \(updatedAtString)")
        }

        if let discogsImageURLString, URL(string: discogsImageURLString) == nil {
            throw GRDBRepositoryError.invalidURL(discogsImageURLString)
        }

        return ImageAsset(
            id: id,
            recordID: recordID,
            discogsImageURL: discogsImageURLString.flatMap(URL.init(string:)),
            thumbnailLocalPath: row["thumbnail_local_path"],
            fullsizeLocalPath: row["fullsize_local_path"],
            pixelWidth: row["pixel_width"],
            pixelHeight: row["pixel_height"],
            byteSize: row["byte_size"],
            lastAccessedAt: lastAccessedAtString.flatMap(DatabaseDateCodec.decode),
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
