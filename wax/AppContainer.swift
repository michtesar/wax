import Combine
import Foundation
import SwiftUI

struct AppContainer: Sendable {
    let databaseManager: GRDBDatabaseManager
    let database: DatabaseContainer

    init(configuration: DatabaseConfiguration = DatabaseConfiguration()) {
        let databaseManager = GRDBDatabaseManager(configuration: configuration)
        self.databaseManager = databaseManager
        self.database = DatabaseContainer(databaseManager: databaseManager)
    }

    @MainActor
    func makeCollectionStore() -> CollectionStore {
        CollectionStore(
            databaseManager: databaseManager,
            recordRepository: database.records
        )
    }

    static func live() -> AppContainer {
        AppContainer(configuration: .live)
    }
}

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var records: [Record] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?

    private let databaseManager: any DatabaseManaging
    private let recordRepository: any RecordRepository

    init(
        databaseManager: any DatabaseManaging,
        recordRepository: any RecordRepository
    ) {
        self.databaseManager = databaseManager
        self.recordRepository = recordRepository
    }

    func bootstrap() async {
        guard !isLoading else {
            return
        }

        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            try await databaseManager.prepareDatabase()
            records = try await recordRepository.fetchRecords(matching: RecordListQuery(limit: 200))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            records = try await recordRepository.fetchRecords(matching: RecordListQuery(limit: 200))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension DatabaseConfiguration {
    static var live: DatabaseConfiguration {
        let processInfo = ProcessInfo.processInfo
        let arguments = Set(processInfo.arguments)
        let environment = processInfo.environment
        let enablesDevelopmentSeed =
            arguments.contains("--seed-development-data") ||
            environment["WAX_SEED_DEVELOPMENT_DATA"] == "1"

        return DatabaseConfiguration(enablesDevelopmentSeed: enablesDevelopmentSeed)
    }
}
