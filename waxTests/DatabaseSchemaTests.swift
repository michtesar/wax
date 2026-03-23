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
}
