import Foundation

struct Record: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    let discogsID: Int?
    var title: String
    var artist: String
    var year: Int?
    var format: String?
    var notes: String
    var condition: RecordCondition?
    var syncStatus: SyncStatus
    var createdAt: Date
    var updatedAt: Date

    init(
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
    let id: UUID
    let recordID: UUID
    let discogsInstanceID: Int?
    var folderID: Int?
    var dateAdded: Date?
    var sortPosition: Int?
    var syncStatus: SyncStatus
    var createdAt: Date
    var updatedAt: Date

    init(
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
    let id: UUID
    let entityType: SyncEntityType
    let entityID: UUID
    var operationType: SyncOperationType
    var payload: Data?
    var state: SyncOperationState
    var attemptCount: Int
    var nextAttemptAt: Date?
    var lastErrorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(
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
    let id: UUID
    var scope: SyncScope
    var cursor: String?
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
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
    let id: UUID
    let recordID: UUID
    var discogsImageURL: URL?
    var thumbnailLocalPath: String?
    var fullsizeLocalPath: String?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteSize: Int64?
    var lastAccessedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
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
