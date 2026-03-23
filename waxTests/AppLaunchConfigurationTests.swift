import Testing
@testable import wax

struct AppLaunchConfigurationTests {
    @Test
    func defaultsToLocalOnlyBootstrap() {
        let configuration = AppLaunchConfiguration.from(
            arguments: [],
            environment: [:]
        )

        if case .localOnly = configuration.bootstrapMode {
            #expect(Bool(true))
        } else {
            Issue.record("Expected localOnly bootstrap mode.")
        }
        #expect(!configuration.databaseConfiguration.enablesDevelopmentSeed)
    }

    @Test
    func enablesDevelopmentSeedFromLegacyFlag() {
        let configuration = AppLaunchConfiguration.from(
            arguments: ["wax", "--seed-development-data"],
            environment: [:]
        )

        if case .developmentSeed = configuration.bootstrapMode {
            #expect(Bool(true))
        } else {
            Issue.record("Expected developmentSeed bootstrap mode.")
        }
        #expect(configuration.databaseConfiguration.enablesDevelopmentSeed)
    }

    @Test
    func enablesDevelopmentSeedFromExplicitBootstrapMode() {
        let configuration = AppLaunchConfiguration.from(
            arguments: ["wax", "--bootstrap-mode=fake-seed"],
            environment: [:]
        )

        if case .developmentSeed = configuration.bootstrapMode {
            #expect(Bool(true))
        } else {
            Issue.record("Expected developmentSeed bootstrap mode.")
        }
        #expect(configuration.databaseConfiguration.enablesDevelopmentSeed)
    }

    @Test
    func configuresDiscogsBootstrapFromArguments() {
        let configuration = AppLaunchConfiguration.from(
            arguments: ["wax", "--bootstrap-mode=discogs", "--discogs-username=tesar"],
            environment: [:]
        )

        switch configuration.bootstrapMode {
        case let .discogs(request):
            #expect(request.username == "tesar")
        default:
            Issue.record("Expected discogs bootstrap mode.")
        }
        #expect(!configuration.databaseConfiguration.enablesDevelopmentSeed)
    }

    @Test
    func configuresDiscogsBootstrapFromEnvironment() {
        let configuration = AppLaunchConfiguration.from(
            arguments: ["wax"],
            environment: [
                "WAX_BOOTSTRAP_MODE": "discogs",
                "WAX_DISCOGS_USERNAME": "crate-user"
            ]
        )

        switch configuration.bootstrapMode {
        case let .discogs(request):
            #expect(request.username == "crate-user")
        default:
            Issue.record("Expected discogs bootstrap mode.")
        }
    }

    @Test
    func configuresCustomDatabaseFileAndResetBehavior() {
        let configuration = AppLaunchConfiguration.from(
            arguments: ["wax", "--sqlite-file-name=preview.sqlite", "--reset-database"],
            environment: [:]
        )

        #expect(configuration.databaseConfiguration.sqliteFileName == "preview.sqlite")
        #expect(configuration.databaseConfiguration.resetsDatabaseOnLaunch)
    }
}
