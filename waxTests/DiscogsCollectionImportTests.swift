import Foundation
import Testing
@testable import wax

struct DiscogsCollectionImportTests {
    @Test
    func importerPersistsRecordsEntriesImagesAndCheckpoint() async throws {
        let harness = try DiscogsImportTestHarness()
        let apiClient = TestDiscogsCollectionAPIClient()
        apiClient.pages = [
            DiscogsCollectionPage(
                pagination: DiscogsPagination(page: 1, pages: 1, perPage: 100, items: 1),
                releases: [
                    DiscogsCollectionRelease(
                        instanceID: 9001,
                        folderID: 1,
                        dateAdded: Date(timeIntervalSince1970: 10_000),
                        basicInformation: DiscogsBasicInformation(
                            id: 42,
                            title: "Discovery",
                            year: 2001,
                            coverImageURL: URL(string: "https://img.discogs.com/discovery.jpg"),
                            artists: [DiscogsArtist(name: "Daft Punk")],
                            formats: [DiscogsFormat(name: "Vinyl", descriptions: ["LP", "Album"])]
                        )
                    )
                ]
            )
        ]

        let importer = DiscogsCollectionImporter(
            apiClient: apiClient,
            recordRepository: harness.recordRepository,
            collectionRepository: harness.collectionRepository,
            imageAssetRepository: harness.imageAssetRepository,
            checkpointRepository: harness.checkpointRepository
        )

        let importedCount = try await importer.importCollection(
            username: "crate-user",
            credentials: DiscogsCredentials(
                oauthToken: "token",
                oauthTokenSecret: "secret",
                username: "crate-user"
            )
        )

        let records = try await harness.recordRepository.fetchRecords(matching: RecordListQuery(limit: 10))
        let entries = try await harness.collectionRepository.fetchEntries(limit: 10, offset: 0)
        let asset = try await harness.imageAssetRepository.fetchImageAsset(recordID: records[0].id)
        let checkpoint = try await harness.checkpointRepository.checkpoint(for: .collectionBootstrap)

        #expect(importedCount == 1)
        #expect(records.count == 1)
        #expect(records.first?.title == "Discovery")
        #expect(records.first?.artist == "Daft Punk")
        #expect(records.first?.format == "Vinyl, LP, Album")
        #expect(entries.first?.discogsInstanceID == 9001)
        #expect(asset?.discogsImageURL?.absoluteString == "https://img.discogs.com/discovery.jpg")
        #expect(checkpoint?.lastSyncedAt != nil)
    }

    @Test
    func importerFetchesAllPages() async throws {
        let harness = try DiscogsImportTestHarness()
        let apiClient = TestDiscogsCollectionAPIClient()
        apiClient.pages = [
            DiscogsCollectionPage(
                pagination: DiscogsPagination(page: 1, pages: 2, perPage: 1, items: 2),
                releases: [
                    DiscogsCollectionRelease(
                        instanceID: 1,
                        folderID: 1,
                        dateAdded: Date(timeIntervalSince1970: 10_001),
                        basicInformation: DiscogsBasicInformation(
                            id: 1,
                            title: "Moon Safari",
                            year: 1998,
                            coverImageURL: nil,
                            artists: [DiscogsArtist(name: "Air")],
                            formats: []
                        )
                    )
                ]
            ),
            DiscogsCollectionPage(
                pagination: DiscogsPagination(page: 2, pages: 2, perPage: 1, items: 2),
                releases: [
                    DiscogsCollectionRelease(
                        instanceID: 2,
                        folderID: 1,
                        dateAdded: Date(timeIntervalSince1970: 10_002),
                        basicInformation: DiscogsBasicInformation(
                            id: 2,
                            title: "Mezzanine",
                            year: 1998,
                            coverImageURL: nil,
                            artists: [DiscogsArtist(name: "Massive Attack")],
                            formats: []
                        )
                    )
                ]
            )
        ]

        let importer = DiscogsCollectionImporter(
            apiClient: apiClient,
            recordRepository: harness.recordRepository,
            collectionRepository: harness.collectionRepository,
            imageAssetRepository: harness.imageAssetRepository,
            checkpointRepository: harness.checkpointRepository
        )

        let importedCount = try await importer.importCollection(
            username: "crate-user",
            credentials: DiscogsCredentials(
                oauthToken: "token",
                oauthTokenSecret: "secret",
                username: "crate-user"
            )
        )

        let records = try await harness.recordRepository.fetchRecords(matching: RecordListQuery(limit: 10))

        #expect(importedCount == 2)
        #expect(apiClient.requestedPages == [1, 2])
        #expect(records.count == 2)
    }
}

@MainActor
struct CollectionStoreDiscogsImportTests {
    @Test
    func importDiscogsCollectionUpdatesStatusAndReloadsRecords() async {
        let importer = TestDiscogsCollectionImporter()
        let repository = StoreImportRecordRepository()
        let manager = StoreImportDatabaseManager()
        repository.fetchResult = [
            Record(
                discogsID: 77,
                title: "Aja",
                artist: "Steely Dan",
                createdAt: Date(timeIntervalSince1970: 11_000),
                updatedAt: Date(timeIntervalSince1970: 11_000)
            )
        ]
        importer.importedCount = 1
        let store = CollectionStore(
            databaseManager: manager,
            recordRepository: repository,
            imageAssetRepository: StoreImportImageAssetRepository(),
            collectionImporter: importer
        )

        await store.importDiscogsCollection(
            credentials: DiscogsCredentials(
                oauthToken: "token",
                oauthTokenSecret: "secret",
                username: "crate-user"
            )
        )

        #expect(importer.importCallCount == 1)
        #expect(store.records.count == 1)
        #expect(store.bootstrapStatusMessage == "Imported 1 records from Discogs.")
    }
}

private final class TestDiscogsCollectionAPIClient: DiscogsCollectionAPIClienting, @unchecked Sendable {
    var pages: [DiscogsCollectionPage] = []
    var requestedPages: [Int] = []

    func fetchCollectionReleases(
        username: String,
        credentials: DiscogsCredentials,
        page: Int,
        perPage: Int
    ) async throws -> DiscogsCollectionPage {
        requestedPages.append(page)
        return pages[page - 1]
    }
}

private final class TestDiscogsCollectionImporter: DiscogsCollectionImporting, @unchecked Sendable {
    var importCallCount = 0
    var importedCount = 0

    func importCollection(username: String, credentials: DiscogsCredentials) async throws -> Int {
        importCallCount += 1
        return importedCount
    }
}

private final class StoreImportDatabaseManager: DatabaseManaging, @unchecked Sendable {
    let configuration = DatabaseConfiguration(sqliteFileName: "test.sqlite")

    func prepareDatabase() async throws {}
}

private final class StoreImportRecordRepository: RecordRepository, @unchecked Sendable {
    var fetchResult: [Record] = []

    func fetchRecords(matching query: RecordListQuery) async throws -> [Record] {
        fetchResult
    }

    func fetchRecord(id: UUID) async throws -> Record? { nil }
    func fetchRecord(discogsID: Int) async throws -> Record? { nil }
    func upsert(_ record: Record) async throws {}
    func deleteRecord(id: UUID) async throws {}
    func updateNotes(recordID: UUID, notes: String, updatedAt: Date) async throws {}
    func updateCondition(recordID: UUID, condition: RecordCondition?, updatedAt: Date) async throws {}
}

private final class StoreImportImageAssetRepository: ImageAssetRepository, @unchecked Sendable {
    func fetchImageAsset(recordID: UUID) async throws -> ImageAsset? { nil }
    func upsert(_ asset: ImageAsset) async throws {}
    func markAccess(recordID: UUID, at date: Date) async throws {}
    func deleteImageAsset(id: UUID) async throws {}
}

private final class DiscogsImportTestHarness {
    let configuration: DatabaseConfiguration
    let manager: GRDBDatabaseManager
    let recordRepository: GRDBRecordRepository
    let collectionRepository: GRDBCollectionRepository
    let imageAssetRepository: GRDBImageAssetRepository
    let checkpointRepository: GRDBSyncCheckpointRepository
    let databaseURL: URL

    init() throws {
        configuration = DatabaseConfiguration(
            sqliteFileName: "wax-discogs-import-tests-\(UUID().uuidString).sqlite"
        )
        manager = GRDBDatabaseManager(configuration: configuration)
        recordRepository = GRDBRecordRepository(databaseManager: manager)
        collectionRepository = GRDBCollectionRepository(databaseManager: manager)
        imageAssetRepository = GRDBImageAssetRepository(databaseManager: manager)
        checkpointRepository = GRDBSyncCheckpointRepository(databaseManager: manager)
        databaseURL = try configuration.databaseURL()
    }

    deinit {
        try? FileManager.default.removeItem(at: databaseURL)
    }
}
