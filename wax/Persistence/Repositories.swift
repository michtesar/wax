import Foundation

struct RecordListQuery: Sendable {
    var searchText: String?
    var syncStatuses: Set<SyncStatus>
    var limit: Int
    var offset: Int

    init(
        searchText: String? = nil,
        syncStatuses: Set<SyncStatus> = [],
        limit: Int = 50,
        offset: Int = 0
    ) {
        self.searchText = searchText
        self.syncStatuses = syncStatuses
        self.limit = limit
        self.offset = offset
    }
}

protocol RecordRepository: Sendable {
    func fetchRecords(matching query: RecordListQuery) async throws -> [Record]
    func fetchRecord(id: UUID) async throws -> Record?
    func fetchRecord(discogsID: Int) async throws -> Record?
    func upsert(_ record: Record) async throws
    func deleteRecord(id: UUID) async throws
    func updateNotes(recordID: UUID, notes: String, updatedAt: Date) async throws
    func updateCondition(recordID: UUID, condition: RecordCondition?, updatedAt: Date) async throws
}

protocol CollectionRepository: Sendable {
    func fetchEntries(limit: Int, offset: Int) async throws -> [CollectionEntry]
    func fetchEntry(id: UUID) async throws -> CollectionEntry?
    func upsert(_ entry: CollectionEntry) async throws
    func deleteEntry(id: UUID) async throws
    func markSyncStatus(entryID: UUID, status: SyncStatus, updatedAt: Date) async throws
}

protocol SyncOperationRepository: Sendable {
    func enqueue(_ operation: SyncOperation) async throws
    func fetchPendingOperations(limit: Int, asOf date: Date) async throws -> [SyncOperation]
    func update(_ operation: SyncOperation) async throws
    func deleteOperation(id: UUID) async throws
}

protocol SyncCheckpointRepository: Sendable {
    func checkpoint(for scope: SyncScope) async throws -> SyncCheckpoint?
    func save(_ checkpoint: SyncCheckpoint) async throws
}

protocol ImageAssetRepository: Sendable {
    func fetchImageAsset(recordID: UUID) async throws -> ImageAsset?
    func upsert(_ asset: ImageAsset) async throws
    func markAccess(recordID: UUID, at date: Date) async throws
    func deleteImageAsset(id: UUID) async throws
}
