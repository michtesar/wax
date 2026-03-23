import Foundation
import Testing
@testable import wax

struct DatabaseSchemaTests {
    @Test
    func migrationPlanIncludesCoreTablesAndIndexes() {
        #expect(DatabaseSchema.migrations.count == 1)

        let statements = DatabaseSchema.migrations[0].statements.joined(separator: "\n")

        #expect(statements.contains("CREATE TABLE IF NOT EXISTS record"))
        #expect(statements.contains("CREATE TABLE IF NOT EXISTS collection_entry"))
        #expect(statements.contains("CREATE TABLE IF NOT EXISTS sync_operation"))
        #expect(statements.contains("CREATE TABLE IF NOT EXISTS sync_checkpoint"))
        #expect(statements.contains("CREATE TABLE IF NOT EXISTS image_asset"))
        #expect(statements.contains("idx_record_discogs_id"))
        #expect(statements.contains("idx_record_updated_at"))
        #expect(statements.contains("idx_record_sync_status"))
    }

    @Test
    func recordIdentityKeepsLocalAndRemoteIdentifiersSeparate() {
        let timestamp = Date(timeIntervalSince1970: 0)
        let record = Record(
            discogsID: 42,
            title: "Discovery",
            artist: "Daft Punk",
            createdAt: timestamp,
            updatedAt: timestamp
        )

        #expect(record.id != UUID())
        #expect(record.discogsID == 42)
    }

    @Test
    func grdbRecordRepositoryRoundTripsRecord() async throws {
        let harness = try DatabaseTestHarness(enablesDevelopmentSeed: true)
        let manager = harness.manager
        let repository = GRDBRecordRepository(databaseManager: manager)
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let record = Record(
            discogsID: 99,
            title: "Moon Safari",
            artist: "Air",
            year: 1998,
            format: "LP",
            notes: "Bootstrapped",
            condition: .nearMint,
            syncStatus: .pending,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await manager.prepareDatabase()
        try await repository.upsert(record)

        let fetched = try await repository.fetchRecord(discogsID: 99)

        #expect(fetched?.title == "Moon Safari")
        #expect(fetched?.artist == "Air")
        #expect(fetched?.condition == .nearMint)
        #expect(fetched?.syncStatus == .pending)
        #expect(fetched?.format == "LP")
    }

    @Test
    func dateCodecDecodesFractionalIso8601AndSQLiteDates() {
        let date = Date(timeIntervalSince1970: 1_000)
        let fractional = DatabaseDateCodec.encode(date)
        let nonFractional = "1970-01-01T00:16:40Z"
        let sqliteTimestamp = "1970-01-01 00:16:40"

        #expect(DatabaseDateCodec.decode(fractional) == date)
        #expect(DatabaseDateCodec.decode(nonFractional) == date)
        #expect(DatabaseDateCodec.decode(sqliteTimestamp) == date)
    }

    @Test
    func recordRepositoryQueryFiltersBySearchAndSyncStatus() async throws {
        let harness = try DatabaseTestHarness()
        let repository = GRDBRecordRepository(databaseManager: harness.manager)
        let timestamp = Date(timeIntervalSince1970: 2_000)

        try await harness.manager.prepareDatabase()
        try await repository.upsert(
            Record(
                discogsID: 1,
                title: "Discovery",
                artist: "Daft Punk",
                syncStatus: .synced,
                createdAt: timestamp,
                updatedAt: timestamp
            )
        )
        try await repository.upsert(
            Record(
                discogsID: 2,
                title: "Homework",
                artist: "Daft Punk",
                syncStatus: .pending,
                createdAt: timestamp,
                updatedAt: timestamp.addingTimeInterval(10)
            )
        )
        try await repository.upsert(
            Record(
                discogsID: 3,
                title: "Moon Safari",
                artist: "Air",
                syncStatus: .failed,
                createdAt: timestamp,
                updatedAt: timestamp.addingTimeInterval(20)
            )
        )

        let result = try await repository.fetchRecords(
            matching: RecordListQuery(
                searchText: "daft",
                syncStatuses: [.pending]
            )
        )

        #expect(result.count == 1)
        #expect(result.first?.title == "Homework")
    }

    @Test
    func collectionRepositoryRoundTripsEntry() async throws {
        let harness = try DatabaseTestHarness()
        let timestamp = Date(timeIntervalSince1970: 3_000)
        let recordRepository = GRDBRecordRepository(databaseManager: harness.manager)
        let repository = GRDBCollectionRepository(databaseManager: harness.manager)
        let record = Record(
            discogsID: 12,
            title: "Promises",
            artist: "Floating Points",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let entry = CollectionEntry(
            recordID: record.id,
            discogsInstanceID: 55,
            folderID: 1,
            dateAdded: timestamp,
            sortPosition: 3,
            syncStatus: .syncing,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await harness.manager.prepareDatabase()
        try await recordRepository.upsert(record)
        try await repository.upsert(entry)

        let fetched = try await repository.fetchEntry(id: entry.id)

        #expect(fetched?.recordID == record.id)
        #expect(fetched?.discogsInstanceID == 55)
        #expect(fetched?.syncStatus == .syncing)
    }

    @Test
    func syncOperationRepositoryRespectsRetrySchedule() async throws {
        let harness = try DatabaseTestHarness()
        let repository = GRDBSyncOperationRepository(databaseManager: harness.manager)
        let timestamp = Date(timeIntervalSince1970: 4_000)
        let eligible = SyncOperation(
            entityType: .record,
            entityID: UUID(),
            operationType: .insert,
            state: .pending,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let deferred = SyncOperation(
            entityType: .record,
            entityID: UUID(),
            operationType: .update,
            state: .failed,
            attemptCount: 1,
            nextAttemptAt: timestamp.addingTimeInterval(120),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await harness.manager.prepareDatabase()
        try await repository.enqueue(eligible)
        try await repository.enqueue(deferred)

        let fetched = try await repository.fetchPendingOperations(limit: 10, asOf: timestamp.addingTimeInterval(60))

        #expect(fetched.count == 1)
        #expect(fetched.first?.id == eligible.id)
    }

    @Test
    func syncCheckpointRepositoryReadsDevelopmentSeedTimestamp() async throws {
        let harness = try DatabaseTestHarness(enablesDevelopmentSeed: true)
        let repository = GRDBSyncCheckpointRepository(databaseManager: harness.manager)

        try await harness.manager.prepareDatabase()
        let checkpoint = try await repository.checkpoint(for: .collectionBootstrap)

        #expect(checkpoint != nil)
        #expect(checkpoint?.scope == .collectionBootstrap)
    }

    @Test
    func developmentSeedInsertsSampleCollectionRecords() async throws {
        let harness = try DatabaseTestHarness(enablesDevelopmentSeed: true)
        let repository = GRDBRecordRepository(databaseManager: harness.manager)

        try await harness.manager.prepareDatabase()
        let records = try await repository.fetchRecords(matching: RecordListQuery(limit: 20))

        #expect(records.count == 3)
        #expect(records.map(\.title).contains("Moon Safari"))
        #expect(records.map(\.title).contains("Discovery"))
        #expect(records.map(\.title).contains("Kind of Blue"))
    }

    @Test
    func syncCheckpointRepositoryUpdatesExistingScope() async throws {
        let harness = try DatabaseTestHarness()
        let repository = GRDBSyncCheckpointRepository(databaseManager: harness.manager)
        let timestamp = Date(timeIntervalSince1970: 5_000)
        var checkpoint = SyncCheckpoint(
            scope: .images,
            cursor: "page-1",
            lastSyncedAt: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await harness.manager.prepareDatabase()
        try await repository.save(checkpoint)

        checkpoint.cursor = "page-2"
        checkpoint.lastSyncedAt = timestamp.addingTimeInterval(5)
        checkpoint.updatedAt = timestamp.addingTimeInterval(5)
        try await repository.save(checkpoint)

        let fetched = try await repository.checkpoint(for: .images)

        #expect(fetched?.cursor == "page-2")
        #expect(fetched?.lastSyncedAt == timestamp.addingTimeInterval(5))
    }

    @Test
    func imageAssetRepositoryRoundTripsAssetAndAccessDate() async throws {
        let harness = try DatabaseTestHarness()
        let timestamp = Date(timeIntervalSince1970: 6_000)
        let recordRepository = GRDBRecordRepository(databaseManager: harness.manager)
        let repository = GRDBImageAssetRepository(databaseManager: harness.manager)
        let record = Record(
            discogsID: 21,
            title: "Selected Ambient Works 85-92",
            artist: "Aphex Twin",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let asset = ImageAsset(
            recordID: record.id,
            discogsImageURL: URL(string: "https://example.com/cover.jpg"),
            thumbnailLocalPath: "thumb.jpg",
            fullsizeLocalPath: "full.jpg",
            pixelWidth: 600,
            pixelHeight: 600,
            byteSize: 1_024,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try await harness.manager.prepareDatabase()
        try await recordRepository.upsert(record)
        try await repository.upsert(asset)
        try await repository.markAccess(recordID: record.id, at: timestamp.addingTimeInterval(30))

        let fetched = try await repository.fetchImageAsset(recordID: record.id)

        #expect(fetched?.thumbnailLocalPath == "thumb.jpg")
        #expect(fetched?.lastAccessedAt == timestamp.addingTimeInterval(30))
    }
}

private final class DatabaseTestHarness {
    let configuration: DatabaseConfiguration
    let manager: GRDBDatabaseManager
    let databaseURL: URL

    init(enablesDevelopmentSeed: Bool = false) throws {
        configuration = DatabaseConfiguration(
            sqliteFileName: "wax-tests-\(UUID().uuidString).sqlite",
            enablesDevelopmentSeed: enablesDevelopmentSeed
        )
        manager = GRDBDatabaseManager(configuration: configuration)
        databaseURL = try configuration.databaseURL()
    }

    deinit {
        try? FileManager.default.removeItem(at: databaseURL)
    }
}
