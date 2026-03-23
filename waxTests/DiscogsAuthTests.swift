import AuthenticationServices
import Foundation
import Testing
@testable import wax

struct DiscogsAuthTests {
    @Test
    func liveConfigurationReadsEnvironmentOverrides() {
        let configurationStore = InMemoryAuthConfigurationStore()
        let configuration = DiscogsAuthConfiguration.live(
            bundle: .main,
            processInfo: TestProcessInfo(
                environment: [
                    "WAX_DISCOGS_CONSUMER_KEY": "consumer-key",
                    "WAX_DISCOGS_CONSUMER_SECRET": "consumer-secret",
                    "WAX_DISCOGS_CALLBACK_SCHEME": "wax-dev",
                    "WAX_DISCOGS_CALLBACK_URL": "wax-dev://discogs/auth"
                ]
            ),
            configurationStore: configurationStore
        )

        #expect(configuration?.consumerKey == "consumer-key")
        #expect(configuration?.consumerSecret == "consumer-secret")
        #expect(configuration?.callbackScheme == "wax-dev")
        #expect(configuration?.callbackURL.absoluteString == "wax-dev://discogs/auth")
        #expect(configurationStore.configuration?.consumerKey == "consumer-key")
    }

    @Test
    func liveConfigurationReturnsNilWithoutCredentials() {
        let configurationStore = InMemoryAuthConfigurationStore()
        let configuration = DiscogsAuthConfiguration.live(
            bundle: .main,
            processInfo: TestProcessInfo(environment: [:]),
            configurationStore: configurationStore
        )

        #expect(configuration == nil)
    }

    @Test
    func liveConfigurationFallsBackToPersistedConfiguration() {
        let configurationStore = InMemoryAuthConfigurationStore()
        try? configurationStore.saveConfiguration(
            PersistedDiscogsAuthConfiguration(
                consumerKey: "persisted-key",
                consumerSecret: "persisted-secret",
                callbackScheme: "wax",
                callbackURL: URL(string: "wax://discogs/auth")!
            )
        )

        let configuration = DiscogsAuthConfiguration.live(
            bundle: .main,
            processInfo: TestProcessInfo(environment: [:]),
            configurationStore: configurationStore
        )

        #expect(configuration?.consumerKey == "persisted-key")
        #expect(configuration?.consumerSecret == "persisted-secret")
        #expect(configuration?.callbackURL.absoluteString == "wax://discogs/auth")
    }

    @Test
    @MainActor
    func authStoreReportsReadinessWhenOAuthConfigurationExists() {
        let store = DiscogsAuthStore(
            authClient: TestDiscogsOAuthClient(),
            credentialStore: InMemoryCredentialStore()
        )

        switch store.readiness {
        case let .ready(callbackURL):
            #expect(callbackURL == "wax://discogs/auth")
        default:
            Issue.record("Expected ready auth state.")
        }
        #expect(store.readinessMessage == "Discogs OAuth ready. Callback: wax://discogs/auth")
    }

    @Test
    @MainActor
    func authStoreReportsMissingConfigurationWhenOAuthConfigurationDoesNotExist() {
        let store = DiscogsAuthStore(
            authClient: nil,
            credentialStore: InMemoryCredentialStore()
        )

        switch store.readiness {
        case let .unavailable(reason):
            #expect(reason.contains("Missing Discogs OAuth consumer key/secret"))
        default:
            Issue.record("Expected unavailable auth state.")
        }
    }
}

@MainActor
struct DiscogsAuthStoreTests {
    @Test
    func restoreSessionLoadsStoredCredentials() async {
        let credentialStore = InMemoryCredentialStore()
        try? credentialStore.saveCredentials(
            DiscogsCredentials(
                oauthToken: "token",
                oauthTokenSecret: "secret",
                username: "crate-user"
            )
        )
        let store = DiscogsAuthStore(
            authClient: TestDiscogsOAuthClient(),
            credentialStore: credentialStore
        )

        await store.restoreSession()

        #expect(store.credentials?.username == "crate-user")
        if case let .signedIn(username) = store.sessionState {
            #expect(username == "crate-user")
        } else {
            Issue.record("Expected restored signed-in session.")
        }
    }

    @Test
    func signInRequestsTokenFetchesIdentityAndPersistsCredentials() async {
        let authClient = TestDiscogsOAuthClient()
        authClient.requestTokenResult = DiscogsOAuthRequestToken(token: "request-token", secret: "request-secret")
        authClient.accessTokenResult = DiscogsCredentials(
            oauthToken: "access-token",
            oauthTokenSecret: "access-secret",
            username: ""
        )
        authClient.identityResult = DiscogsIdentity(username: "discogs-user")
        let credentialStore = InMemoryCredentialStore()
        let store = DiscogsAuthStore(
            authClient: authClient,
            credentialStore: credentialStore
        )

        await store.signIn { url, callbackScheme in
            #expect(url.absoluteString.contains("oauth_token=request-token"))
            #expect(callbackScheme == "wax")
            return URL(string: "wax://discogs/auth?oauth_token=request-token&oauth_verifier=verifier")!
        }

        #expect(authClient.requestTokenCallCount == 1)
        #expect(authClient.exchangeTokenCallCount == 1)
        #expect(authClient.fetchIdentityCallCount == 1)
        #expect(credentialStore.credentials?.username == "discogs-user")
        if case let .signedIn(username) = store.sessionState {
            #expect(username == "discogs-user")
        } else {
            Issue.record("Expected signed-in state after successful Discogs auth.")
        }
    }

    @Test
    func signOutClearsStoredCredentials() async {
        let credentialStore = InMemoryCredentialStore()
        try? credentialStore.saveCredentials(
            DiscogsCredentials(
                oauthToken: "token",
                oauthTokenSecret: "secret",
                username: "crate-user"
            )
        )
        let store = DiscogsAuthStore(
            authClient: TestDiscogsOAuthClient(),
            credentialStore: credentialStore
        )

        await store.restoreSession()
        store.signOut()

        #expect(credentialStore.credentials == nil)
        if case .signedOut = store.sessionState {
            #expect(Bool(true))
        } else {
            Issue.record("Expected signed-out state after logout.")
        }
    }

    @Test
    func signInWithoutConfigurationSurfacesUnavailableState() async {
        let store = DiscogsAuthStore(
            authClient: nil,
            credentialStore: InMemoryCredentialStore()
        )

        await store.signIn { _, _ in
            Issue.record("Presenter should not be called without auth config.")
            return URL(string: "wax://discogs/auth")!
        }

        if case .unavailable = store.sessionState {
            #expect(Bool(true))
        } else {
            Issue.record("Expected unavailable state when auth config is missing.")
        }
        #expect(store.errorMessage == DiscogsAuthError.missingConfiguration.localizedDescription)
    }
}

private struct TestProcessInfo: _DiscogsProcessInfo {
    let environment: [String: String]
}

private final class TestDiscogsOAuthClient: DiscogsOAuthClienting, @unchecked Sendable {
    let configuration = DiscogsAuthConfiguration(
        consumerKey: "consumer-key",
        consumerSecret: "consumer-secret",
        callbackScheme: "wax",
        callbackURL: URL(string: "wax://discogs/auth")!
    )

    var requestTokenResult = DiscogsOAuthRequestToken(token: "request-token", secret: "request-secret")
    var accessTokenResult = DiscogsCredentials(
        oauthToken: "access-token",
        oauthTokenSecret: "access-secret",
        username: "crate-user"
    )
    var identityResult = DiscogsIdentity(username: "crate-user")
    var requestTokenCallCount = 0
    var exchangeTokenCallCount = 0
    var fetchIdentityCallCount = 0

    func requestToken() async throws -> DiscogsOAuthRequestToken {
        requestTokenCallCount += 1
        return requestTokenResult
    }

    func exchangeAccessToken(
        requestToken: DiscogsOAuthRequestToken,
        callbackURL: URL
    ) async throws -> DiscogsCredentials {
        exchangeTokenCallCount += 1
        return accessTokenResult
    }

    func fetchIdentity(credentials: DiscogsCredentials) async throws -> DiscogsIdentity {
        fetchIdentityCallCount += 1
        return identityResult
    }
}

private final class InMemoryCredentialStore: DiscogsCredentialStoring, @unchecked Sendable {
    var credentials: DiscogsCredentials?

    func loadCredentials() throws -> DiscogsCredentials? {
        credentials
    }

    func saveCredentials(_ credentials: DiscogsCredentials) throws {
        self.credentials = credentials
    }

    func clearCredentials() throws {
        credentials = nil
    }
}

private final class InMemoryAuthConfigurationStore: DiscogsAuthConfigurationStoring, @unchecked Sendable {
    var configuration: PersistedDiscogsAuthConfiguration?

    func loadConfiguration() throws -> PersistedDiscogsAuthConfiguration? {
        configuration
    }

    func saveConfiguration(_ configuration: PersistedDiscogsAuthConfiguration) throws {
        self.configuration = configuration
    }

    func clearConfiguration() throws {
        configuration = nil
    }
}
