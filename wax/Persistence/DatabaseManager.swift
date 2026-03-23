import Foundation
import GRDB

struct DatabaseConfiguration: Equatable, Sendable {
    let sqliteFileName: String
    let enablesDevelopmentSeed: Bool
    let resetsDatabaseOnLaunch: Bool

    nonisolated init(
        sqliteFileName: String = "wax.sqlite",
        enablesDevelopmentSeed: Bool = false,
        resetsDatabaseOnLaunch: Bool = false
    ) {
        self.sqliteFileName = sqliteFileName
        self.enablesDevelopmentSeed = enablesDevelopmentSeed
        self.resetsDatabaseOnLaunch = resetsDatabaseOnLaunch
    }

    nonisolated func databaseURL(fileManager: FileManager = .default) throws -> URL {
        try fileManager
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(sqliteFileName, isDirectory: false)
    }
}

enum DatabaseManagerError: Error, LocalizedError, Sendable {
    case databaseUnavailable
    case migrationFailed(migrationID: String, underlyingMessage: String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "Database is unavailable."
        case let .migrationFailed(migrationID, underlyingMessage):
            return "Migration \(migrationID) failed: \(underlyingMessage)"
        }
    }
}

protocol DatabaseManaging: Sendable {
    var configuration: DatabaseConfiguration { get }
    func prepareDatabase() async throws
}

struct DatabaseBootstrapPlan: Sendable {
    nonisolated let configuration: DatabaseConfiguration
    nonisolated let migrations: [DatabaseMigration]
    nonisolated let developmentSeedStatements: [String]

    nonisolated init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
        self.migrations = DatabaseSchema.migrations
        self.developmentSeedStatements = configuration.enablesDevelopmentSeed
            ? DatabaseSchema.developmentSeedStatements
            : []
    }
}

final class GRDBDatabaseManager: DatabaseManaging, @unchecked Sendable {
    let configuration: DatabaseConfiguration

    private var databaseQueue: DatabaseQueue?

    nonisolated init(configuration: DatabaseConfiguration = DatabaseConfiguration()) {
        self.configuration = configuration
    }

    func prepareDatabase() async throws {
        if databaseQueue != nil {
            return
        }

        if configuration.resetsDatabaseOnLaunch {
            try resetDatabaseFiles()
        }

        let queue = try DatabaseQueue(path: databasePath())
        var migrator = DatabaseMigrator()

        for migration in DatabaseSchema.migrations {
            migrator.registerMigration(migration.id) { db in
                do {
                    for statement in migration.statements {
                        try db.execute(sql: statement)
                    }
                } catch {
                    throw DatabaseManagerError.migrationFailed(
                        migrationID: migration.id,
                        underlyingMessage: error.localizedDescription
                    )
                }
            }
        }

        try migrator.migrate(queue)

        if configuration.enablesDevelopmentSeed {
            try await queue.write { db in
                for statement in DatabaseSchema.developmentSeedStatements {
                    try db.execute(sql: statement)
                }
            }
        }

        databaseQueue = queue
    }

    func read<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        let queue = try await queue()
        return try await queue.read(value)
    }

    func write<T: Sendable>(_ value: @Sendable (Database) throws -> T) async throws -> T {
        let queue = try await queue()
        return try await queue.write(value)
    }

    private func queue() async throws -> DatabaseQueue {
        if databaseQueue == nil {
            try await prepareDatabase()
        }

        guard let databaseQueue else {
            throw DatabaseManagerError.databaseUnavailable
        }

        return databaseQueue
    }

    private func databasePath() throws -> String {
        let url = try configuration.databaseURL()
        return url.path(percentEncoded: false)
    }

    private func resetDatabaseFiles(fileManager: FileManager = .default) throws {
        let url = try configuration.databaseURL(fileManager: fileManager)
        let sidecarURLs = [
            url,
            url.appendingPathExtension("shm"),
            url.appendingPathExtension("wal")
        ]

        for sidecarURL in sidecarURLs where fileManager.fileExists(atPath: sidecarURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: sidecarURL)
        }
    }
}
