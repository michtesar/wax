import Foundation
import Testing
@testable import wax

@MainActor
struct CollectionStoreTests {
    @Test
    func bootstrapLoadsRecordsAfterPreparingDatabase() async {
        let manager = TestDatabaseManager()
        let repository = TestRecordRepository()
        let expected = Record(
            discogsID: 7,
            title: "Music Has the Right to Children",
            artist: "Boards of Canada",
            syncStatus: .synced,
            createdAt: Date(timeIntervalSince1970: 7_000),
            updatedAt: Date(timeIntervalSince1970: 7_000)
        )
        repository.fetchResult = [expected]
        let store = CollectionStore(
            databaseManager: manager,
            recordRepository: repository,
            imageAssetRepository: TestImageAssetRepository(),
            bootstrapMode: .developmentSeed
        )

        await store.bootstrap()

        #expect(manager.prepareCallCount == 1)
        #expect(repository.fetchCallCount == 1)
        #expect(store.records == [expected])
        #expect(store.errorMessage == nil)
        #expect(store.bootstrapStatusMessage == "Fake seed loaded for local development.")
        #expect(store.hasLoaded)
        #expect(!store.isLoading)
    }

    @Test
    func bootstrapCapturesRepositoryErrors() async {
        let manager = TestDatabaseManager()
        let repository = TestRecordRepository()
        repository.fetchError = TestFailure.expected
        let store = CollectionStore(
            databaseManager: manager,
            recordRepository: repository,
            imageAssetRepository: TestImageAssetRepository(),
            bootstrapMode: .discogs(DiscogsBootstrapRequest(username: "michael"))
        )

        await store.bootstrap()

        #expect(store.records.isEmpty)
        #expect(store.errorMessage == TestFailure.expected.localizedDescription)
        #expect(store.bootstrapStatusMessage == nil)
        #expect(store.hasLoaded)
    }

    @Test
    func reloadRefreshesVisibleRecords() async {
        let manager = TestDatabaseManager()
        let repository = TestRecordRepository()
        let first = Record(
            discogsID: 1,
            title: "Endtroducing.....",
            artist: "DJ Shadow",
            createdAt: Date(timeIntervalSince1970: 8_000),
            updatedAt: Date(timeIntervalSince1970: 8_000)
        )
        let second = Record(
            discogsID: 2,
            title: "Since I Left You",
            artist: "The Avalanches",
            createdAt: Date(timeIntervalSince1970: 8_100),
            updatedAt: Date(timeIntervalSince1970: 8_100)
        )
        repository.fetchResult = [first]
        let store = CollectionStore(
            databaseManager: manager,
            recordRepository: repository,
            imageAssetRepository: TestImageAssetRepository()
        )

        await store.bootstrap()
        repository.fetchResult = [second]
        await store.reload()

        #expect(store.records == [second])
        #expect(repository.fetchCallCount == 2)
    }
}

private enum TestFailure: Error {
    case expected
}

private final class TestDatabaseManager: DatabaseManaging, @unchecked Sendable {
    let configuration = DatabaseConfiguration(sqliteFileName: "test.sqlite")
    var prepareCallCount = 0

    func prepareDatabase() async throws {
        prepareCallCount += 1
    }
}

private final class TestRecordRepository: RecordRepository, @unchecked Sendable {
    var fetchResult: [Record] = []
    var fetchError: Error?
    var fetchCallCount = 0

    func fetchRecords(matching query: RecordListQuery) async throws -> [Record] {
        fetchCallCount += 1
        if let fetchError {
            throw fetchError
        }
        return fetchResult
    }

    func fetchRecord(id: UUID) async throws -> Record? {
        nil
    }

    func fetchRecord(discogsID: Int) async throws -> Record? {
        nil
    }

    func upsert(_ record: Record) async throws {}

    func deleteRecord(id: UUID) async throws {}

    func updateNotes(recordID: UUID, notes: String, updatedAt: Date) async throws {}

    func updateCondition(recordID: UUID, condition: RecordCondition?, updatedAt: Date) async throws {}
}

private final class TestImageAssetRepository: ImageAssetRepository, @unchecked Sendable {
    func fetchImageAsset(recordID: UUID) async throws -> ImageAsset? { nil }
    func upsert(_ asset: ImageAsset) async throws {}
    func markAccess(recordID: UUID, at date: Date) async throws {}
    func deleteImageAsset(id: UUID) async throws {}
}
