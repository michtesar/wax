import Foundation

struct Record: Identifiable, Hashable, Codable, Sendable {
    nonisolated let id: UUID
    nonisolated let discogsID: Int?
    nonisolated var title: String
    nonisolated var artist: String
    nonisolated var year: Int?
    nonisolated var format: String?
    nonisolated var notes: String
    nonisolated var condition: RecordCondition?
    nonisolated var syncStatus: SyncStatus
    nonisolated var createdAt: Date
    nonisolated var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        discogsID: Int? = nil,
        title: String,
        artist: String,
        year: Int? = nil,
        format: String? = nil,
        notes: String = "",
        condition: RecordCondition? = nil,
        syncStatus: SyncStatus = .synced,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.discogsID = discogsID
        self.title = title
        self.artist = artist
        self.year = year
        self.format = format
        self.notes = notes
        self.condition = condition
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct CollectionEntry: Identifiable, Hashable, Codable, Sendable {
    nonisolated let id: UUID
    nonisolated let recordID: UUID
    nonisolated let discogsInstanceID: Int?
    nonisolated var folderID: Int?
    nonisolated var dateAdded: Date?
    nonisolated var sortPosition: Int?
    nonisolated var syncStatus: SyncStatus
    nonisolated var createdAt: Date
    nonisolated var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        recordID: UUID,
        discogsInstanceID: Int? = nil,
        folderID: Int? = nil,
        dateAdded: Date? = nil,
        sortPosition: Int? = nil,
        syncStatus: SyncStatus = .synced,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.recordID = recordID
        self.discogsInstanceID = discogsInstanceID
        self.folderID = folderID
        self.dateAdded = dateAdded
        self.sortPosition = sortPosition
        self.syncStatus = syncStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SyncOperation: Identifiable, Hashable, Codable, Sendable {
    nonisolated let id: UUID
    nonisolated let entityType: SyncEntityType
    nonisolated let entityID: UUID
    nonisolated var operationType: SyncOperationType
    nonisolated var payload: Data?
    nonisolated var state: SyncOperationState
    nonisolated var attemptCount: Int
    nonisolated var nextAttemptAt: Date?
    nonisolated var lastErrorMessage: String?
    nonisolated var createdAt: Date
    nonisolated var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        entityType: SyncEntityType,
        entityID: UUID,
        operationType: SyncOperationType,
        payload: Data? = nil,
        state: SyncOperationState = .pending,
        attemptCount: Int = 0,
        nextAttemptAt: Date? = nil,
        lastErrorMessage: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.entityType = entityType
        self.entityID = entityID
        self.operationType = operationType
        self.payload = payload
        self.state = state
        self.attemptCount = attemptCount
        self.nextAttemptAt = nextAttemptAt
        self.lastErrorMessage = lastErrorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct SyncCheckpoint: Identifiable, Hashable, Codable, Sendable {
    nonisolated let id: UUID
    nonisolated var scope: SyncScope
    nonisolated var cursor: String?
    nonisolated var lastSyncedAt: Date?
    nonisolated var createdAt: Date
    nonisolated var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        scope: SyncScope,
        cursor: String? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.scope = scope
        self.cursor = cursor
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ImageAsset: Identifiable, Hashable, Codable, Sendable {
    nonisolated let id: UUID
    nonisolated let recordID: UUID
    nonisolated var discogsImageURL: URL?
    nonisolated var thumbnailLocalPath: String?
    nonisolated var fullsizeLocalPath: String?
    nonisolated var pixelWidth: Int?
    nonisolated var pixelHeight: Int?
    nonisolated var byteSize: Int64?
    nonisolated var lastAccessedAt: Date?
    nonisolated var createdAt: Date
    nonisolated var updatedAt: Date

    nonisolated init(
        id: UUID = UUID(),
        recordID: UUID,
        discogsImageURL: URL? = nil,
        thumbnailLocalPath: String? = nil,
        fullsizeLocalPath: String? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        byteSize: Int64? = nil,
        lastAccessedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.recordID = recordID
        self.discogsImageURL = discogsImageURL
        self.thumbnailLocalPath = thumbnailLocalPath
        self.fullsizeLocalPath = fullsizeLocalPath
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.lastAccessedAt = lastAccessedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum RecordCondition: String, Codable, CaseIterable, Sendable {
    case mint = "M"
    case nearMint = "NM"
    case veryGoodPlus = "VG+"
    case veryGood = "VG"
    case goodPlus = "G+"
    case good = "G"
    case fair = "F"
    case poor = "P"
}

enum SyncStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case syncing
    case synced
    case failed
}

enum SyncEntityType: String, Codable, CaseIterable, Sendable {
    case record
    case collectionEntry
    case imageAsset
}

enum SyncOperationType: String, Codable, CaseIterable, Sendable {
    case insert
    case update
    case delete
}

enum SyncOperationState: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case failed
    case deadLetter
    case completed
}

enum SyncScope: String, Codable, CaseIterable, Sendable {
    case collectionBootstrap
    case collectionDelta
    case images
}
