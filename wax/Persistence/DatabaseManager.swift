import Foundation

struct DatabaseConfiguration: Sendable {
    let sqliteFileName: String
    let enablesDevelopmentSeed: Bool

    init(
        sqliteFileName: String = "wax.sqlite",
        enablesDevelopmentSeed: Bool = false
    ) {
        self.sqliteFileName = sqliteFileName
        self.enablesDevelopmentSeed = enablesDevelopmentSeed
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
    let configuration: DatabaseConfiguration
    let migrations: [DatabaseMigration]
    let developmentSeedStatements: [String]

    init(configuration: DatabaseConfiguration) {
        self.configuration = configuration
        self.migrations = DatabaseSchema.migrations
        self.developmentSeedStatements = configuration.enablesDevelopmentSeed
            ? DatabaseSchema.developmentSeedStatements
            : []
    }
}
