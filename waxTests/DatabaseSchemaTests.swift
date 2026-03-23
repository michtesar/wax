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
        let configuration = DatabaseConfiguration(
            sqliteFileName: "wax-tests-\(UUID().uuidString).sqlite",
            enablesDevelopmentSeed: true
        )
        let databaseURL = try configuration.databaseURL()
        let manager = GRDBDatabaseManager(configuration: configuration)
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

        try? FileManager.default.removeItem(at: databaseURL)
    }
}
