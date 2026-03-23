import Combine
import Foundation
import SwiftUI

enum CollectionBootstrapMode: Sendable {
    case localOnly
    case developmentSeed
    case discogs(DiscogsBootstrapRequest)
}

struct DiscogsBootstrapRequest: Sendable {
    let username: String?
}

struct AppLaunchConfiguration: Sendable {
    let databaseConfiguration: DatabaseConfiguration
    let bootstrapMode: CollectionBootstrapMode

    static func live(processInfo: ProcessInfo = .processInfo) -> AppLaunchConfiguration {
        from(
            arguments: processInfo.arguments,
            environment: processInfo.environment
        )
    }

    static func from(
        arguments: [String],
        environment: [String: String]
    ) -> AppLaunchConfiguration {
        let bootstrapMode = bootstrapMode(arguments: arguments, environment: environment)
        let sqliteFileName = sqliteFileName(arguments: arguments, environment: environment)
        let resetsDatabaseOnLaunch = resetsDatabaseOnLaunch(arguments: arguments, environment: environment)
        let databaseConfiguration = DatabaseConfiguration(
            sqliteFileName: sqliteFileName,
            enablesDevelopmentSeed: bootstrapMode.enablesDevelopmentSeed,
            resetsDatabaseOnLaunch: resetsDatabaseOnLaunch
        )

        return AppLaunchConfiguration(
            databaseConfiguration: databaseConfiguration,
            bootstrapMode: bootstrapMode
        )
    }

    private static func bootstrapMode(
        arguments: [String],
        environment: [String: String]
    ) -> CollectionBootstrapMode {
        if arguments.contains("--seed-development-data") || environment["WAX_SEED_DEVELOPMENT_DATA"] == "1" {
            return .developmentSeed
        }

        let argumentMode = arguments
            .first { $0.hasPrefix("--bootstrap-mode=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last.map(String.init) }
        let environmentMode = environment["WAX_BOOTSTRAP_MODE"]
        let rawMode = argumentMode ?? environmentMode

        switch rawMode?.lowercased() {
        case "development-seed", "fake-seed":
            return .developmentSeed
        case "discogs":
            let usernameArgument = arguments
                .first { $0.hasPrefix("--discogs-username=") }
                .flatMap { $0.split(separator: "=", maxSplits: 1).last.map(String.init) }
            let username = usernameArgument ?? environment["WAX_DISCOGS_USERNAME"]
            return .discogs(DiscogsBootstrapRequest(username: username))
        default:
            return .localOnly
        }
    }

    private static func sqliteFileName(
        arguments: [String],
        environment: [String: String]
    ) -> String {
        let argumentValue = arguments
            .first { $0.hasPrefix("--sqlite-file-name=") }
            .flatMap { $0.split(separator: "=", maxSplits: 1).last.map(String.init) }
        return argumentValue ?? environment["WAX_SQLITE_FILE_NAME"] ?? "wax.sqlite"
    }

    private static func resetsDatabaseOnLaunch(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        arguments.contains("--reset-database") || environment["WAX_RESET_DATABASE"] == "1"
    }
}

private extension CollectionBootstrapMode {
    var enablesDevelopmentSeed: Bool {
        if case .developmentSeed = self {
            return true
        }

        return false
    }
}

struct AppContainer: Sendable {
    let launchConfiguration: AppLaunchConfiguration
    let databaseManager: GRDBDatabaseManager
    let database: DatabaseContainer
    let authStore: DiscogsAuthStore
    let collectionImporter: (any DiscogsCollectionImporting)?

    init(launchConfiguration: AppLaunchConfiguration = .live()) {
        self.launchConfiguration = launchConfiguration
        let databaseManager = GRDBDatabaseManager(configuration: launchConfiguration.databaseConfiguration)
        let database = DatabaseContainer(databaseManager: databaseManager)
        let authConfiguration = DiscogsAuthConfiguration.live()
        let authClient = authConfiguration.map { configuration in
            DiscogsOAuthClient(configuration: configuration)
        }
        let collectionImporter = authConfiguration.map { configuration in
            DiscogsCollectionImporter(
                apiClient: DiscogsCollectionAPIClient(configuration: configuration),
                recordRepository: database.records,
                collectionRepository: database.collections,
                imageAssetRepository: database.imageAssets,
                checkpointRepository: database.syncCheckpoints
            )
        }
        self.databaseManager = databaseManager
        self.database = database
        self.authStore = DiscogsAuthStore(
            authClient: authClient,
            credentialStore: KeychainDiscogsCredentialStore()
        )
        self.collectionImporter = collectionImporter
    }

    @MainActor
    func makeStores() -> AppStores {
        AppStores(
            authStore: authStore,
            collectionStore: CollectionStore(
                databaseManager: databaseManager,
                recordRepository: database.records,
                collectionImporter: collectionImporter,
                bootstrapMode: launchConfiguration.bootstrapMode
            )
        )
    }

    @MainActor
    func makeCollectionStore() -> CollectionStore {
        CollectionStore(
            databaseManager: databaseManager,
            recordRepository: database.records,
            collectionImporter: collectionImporter,
            bootstrapMode: launchConfiguration.bootstrapMode
        )
    }

    static func live() -> AppContainer {
        AppContainer(launchConfiguration: .live())
    }
}

@MainActor
struct AppStores {
    let authStore: DiscogsAuthStore
    let collectionStore: CollectionStore
}

@MainActor
final class CollectionStore: ObservableObject {
    @Published private(set) var records: [Record] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published var errorMessage: String?
    @Published private(set) var bootstrapStatusMessage: String?

    private let databaseManager: any DatabaseManaging
    private let recordRepository: any RecordRepository
    private let collectionImporter: (any DiscogsCollectionImporting)?
    private let bootstrapMode: CollectionBootstrapMode

    init(
        databaseManager: any DatabaseManaging,
        recordRepository: any RecordRepository,
        collectionImporter: (any DiscogsCollectionImporting)? = nil,
        bootstrapMode: CollectionBootstrapMode = .localOnly
    ) {
        self.databaseManager = databaseManager
        self.recordRepository = recordRepository
        self.collectionImporter = collectionImporter
        self.bootstrapMode = bootstrapMode
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
            bootstrapStatusMessage = bootstrapStatus(for: bootstrapMode, recordCount: records.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reload() async {
        do {
            records = try await recordRepository.fetchRecords(matching: RecordListQuery(limit: 200))
            errorMessage = nil
            bootstrapStatusMessage = bootstrapStatus(for: bootstrapMode, recordCount: records.count)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importDiscogsCollection(credentials: DiscogsCredentials) async {
        guard let collectionImporter else {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let importedCount = try await collectionImporter.importCollection(
                username: credentials.username,
                credentials: credentials
            )
            records = try await recordRepository.fetchRecords(matching: RecordListQuery(limit: 200))
            errorMessage = nil
            bootstrapStatusMessage = "Imported \(importedCount) records from Discogs."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bootstrapStatus(
        for mode: CollectionBootstrapMode,
        recordCount: Int
    ) -> String? {
        switch mode {
        case .localOnly:
            return nil
        case .developmentSeed:
            return recordCount > 0 ? "Fake seed loaded for local development." : "Fake seed mode is active."
        case let .discogs(request):
            if let username = request.username, !username.isEmpty {
                return "Discogs bootstrap mode configured for \(username)."
            }
            return "Discogs bootstrap mode configured."
        }
    }
}
