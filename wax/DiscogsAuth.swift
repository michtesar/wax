import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security

protocol _DiscogsProcessInfo {
    var environment: [String: String] { get }
}

extension ProcessInfo: _DiscogsProcessInfo {}

struct PersistedDiscogsAuthConfiguration: Codable, Equatable, Sendable {
    let consumerKey: String
    let consumerSecret: String
    let callbackScheme: String
    let callbackURL: URL
}

struct DiscogsAuthConfiguration: Sendable {
    let consumerKey: String
    let consumerSecret: String
    let callbackScheme: String
    let callbackURL: URL
    let userAgent: String

    init(
        consumerKey: String,
        consumerSecret: String,
        callbackScheme: String,
        callbackURL: URL,
        userAgent: String = "wax/1.0"
    ) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.callbackScheme = callbackScheme
        self.callbackURL = callbackURL
        self.userAgent = userAgent
    }

    static func live(
        bundle: Bundle = .main,
        processInfo: any _DiscogsProcessInfo = ProcessInfo.processInfo,
        configurationStore: any DiscogsAuthConfigurationStoring = KeychainDiscogsAuthConfigurationStore()
    ) -> DiscogsAuthConfiguration? {
        let environment = processInfo.environment
        let persistedConfiguration = try? configurationStore.loadConfiguration()
        let consumerKey = environment["WAX_DISCOGS_CONSUMER_KEY"]
            ?? bundle.object(forInfoDictionaryKey: "DiscogsConsumerKey") as? String
            ?? persistedConfiguration?.consumerKey
        let consumerSecret = environment["WAX_DISCOGS_CONSUMER_SECRET"]
            ?? bundle.object(forInfoDictionaryKey: "DiscogsConsumerSecret") as? String
            ?? persistedConfiguration?.consumerSecret
        let callbackScheme = environment["WAX_DISCOGS_CALLBACK_SCHEME"]
            ?? bundle.object(forInfoDictionaryKey: "DiscogsCallbackScheme") as? String
            ?? persistedConfiguration?.callbackScheme
            ?? "wax"
        let callbackURLString = environment["WAX_DISCOGS_CALLBACK_URL"]
            ?? bundle.object(forInfoDictionaryKey: "DiscogsCallbackURL") as? String
            ?? persistedConfiguration?.callbackURL.absoluteString
            ?? "\(callbackScheme)://discogs/auth"

        guard
            let consumerKey,
            !consumerKey.isEmpty,
            let consumerSecret,
            !consumerSecret.isEmpty,
            let callbackURL = URL(string: callbackURLString)
        else {
            return nil
        }

        let configuration = DiscogsAuthConfiguration(
            consumerKey: consumerKey,
            consumerSecret: consumerSecret,
            callbackScheme: callbackScheme,
            callbackURL: callbackURL
        )
        try? configurationStore.saveConfiguration(
            PersistedDiscogsAuthConfiguration(
                consumerKey: configuration.consumerKey,
                consumerSecret: configuration.consumerSecret,
                callbackScheme: configuration.callbackScheme,
                callbackURL: configuration.callbackURL
            )
        )
        return configuration
    }
}

struct DiscogsOAuthRequestToken: Equatable, Sendable {
    let token: String
    let secret: String

    var authorizationURL: URL {
        var components = URLComponents(string: "https://www.discogs.com/oauth/authorize")!
        components.queryItems = [URLQueryItem(name: "oauth_token", value: token)]
        return components.url!
    }
}

struct DiscogsCredentials: Codable, Equatable, Sendable {
    let oauthToken: String
    let oauthTokenSecret: String
    let username: String
}

struct DiscogsIdentity: Equatable, Sendable {
    let username: String
}

enum DiscogsAuthError: LocalizedError, Sendable {
    case missingConfiguration
    case malformedResponse
    case callbackRejected
    case missingOAuthVerifier
    case invalidHTTPStatus(Int)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Discogs auth configuration is missing."
        case .malformedResponse:
            return "Discogs returned an unreadable auth response."
        case .callbackRejected:
            return "Discogs login callback was rejected."
        case .missingOAuthVerifier:
            return "Discogs callback is missing the OAuth verifier."
        case let .invalidHTTPStatus(statusCode):
            return "Discogs request failed with status \(statusCode)."
        case .cancelled:
            return "Discogs login was cancelled."
        }
    }
}

protocol DiscogsNetworking: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: DiscogsNetworking {}

protocol DiscogsOAuthClienting: Sendable {
    var configuration: DiscogsAuthConfiguration { get }
    func requestToken() async throws -> DiscogsOAuthRequestToken
    func exchangeAccessToken(
        requestToken: DiscogsOAuthRequestToken,
        callbackURL: URL
    ) async throws -> DiscogsCredentials
    func fetchIdentity(credentials: DiscogsCredentials) async throws -> DiscogsIdentity
}

struct DiscogsOAuthClient: DiscogsOAuthClienting, Sendable {
    let configuration: DiscogsAuthConfiguration
    let networking: any DiscogsNetworking

    init(
        configuration: DiscogsAuthConfiguration,
        networking: any DiscogsNetworking = URLSession.shared
    ) {
        self.configuration = configuration
        self.networking = networking
    }

    func requestToken() async throws -> DiscogsOAuthRequestToken {
        let endpoint = URL(string: "https://api.discogs.com/oauth/request_token")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            OAuth1Signer.authorizationHeader(
                method: "POST",
                url: endpoint,
                consumerKey: configuration.consumerKey,
                consumerSecret: configuration.consumerSecret,
                token: nil,
                tokenSecret: nil,
                additionalOAuthParameters: [
                    "oauth_callback": configuration.callbackURL.absoluteString
                ]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let response = try await perform(request)
        let parameters = try FormEncodedParser.parse(response.data)

        guard
            let token = parameters["oauth_token"],
            let secret = parameters["oauth_token_secret"]
        else {
            throw DiscogsAuthError.malformedResponse
        }

        return DiscogsOAuthRequestToken(token: token, secret: secret)
    }

    func exchangeAccessToken(
        requestToken: DiscogsOAuthRequestToken,
        callbackURL: URL
    ) async throws -> DiscogsCredentials {
        guard let verifier = callbackURL.oauthQueryValue(named: "oauth_verifier") else {
            throw DiscogsAuthError.missingOAuthVerifier
        }

        let callbackToken = callbackURL.oauthQueryValue(named: "oauth_token")
        guard callbackToken == requestToken.token else {
            throw DiscogsAuthError.callbackRejected
        }

        let endpoint = URL(string: "https://api.discogs.com/oauth/access_token")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            OAuth1Signer.authorizationHeader(
                method: "POST",
                url: endpoint,
                consumerKey: configuration.consumerKey,
                consumerSecret: configuration.consumerSecret,
                token: requestToken.token,
                tokenSecret: requestToken.secret,
                additionalOAuthParameters: [
                    "oauth_verifier": verifier
                ]
            ),
            forHTTPHeaderField: "Authorization"
        )

        let response = try await perform(request)
        let parameters = try FormEncodedParser.parse(response.data)

        guard
            let oauthToken = parameters["oauth_token"],
            let oauthTokenSecret = parameters["oauth_token_secret"]
        else {
            throw DiscogsAuthError.malformedResponse
        }

        return DiscogsCredentials(
            oauthToken: oauthToken,
            oauthTokenSecret: oauthTokenSecret,
            username: parameters["username"] ?? ""
        )
    }

    func fetchIdentity(credentials: DiscogsCredentials) async throws -> DiscogsIdentity {
        let endpoint = URL(string: "https://api.discogs.com/oauth/identity")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(
            OAuth1Signer.authorizationHeader(
                method: "GET",
                url: endpoint,
                consumerKey: configuration.consumerKey,
                consumerSecret: configuration.consumerSecret,
                token: credentials.oauthToken,
                tokenSecret: credentials.oauthTokenSecret
            ),
            forHTTPHeaderField: "Authorization"
        )

        let response = try await perform(request)
        let payload = try JSONDecoder().decode(DiscogsIdentityPayload.self, from: response.data)
        return DiscogsIdentity(username: payload.username)
    }

    private func perform(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsAuthError.malformedResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DiscogsAuthError.invalidHTTPStatus(httpResponse.statusCode)
        }

        return (data, httpResponse)
    }
}

protocol DiscogsCredentialStoring: Sendable {
    func loadCredentials() throws -> DiscogsCredentials?
    func saveCredentials(_ credentials: DiscogsCredentials) throws
    func clearCredentials() throws
}

protocol DiscogsAuthConfigurationStoring: Sendable {
    func loadConfiguration() throws -> PersistedDiscogsAuthConfiguration?
    func saveConfiguration(_ configuration: PersistedDiscogsAuthConfiguration) throws
    func clearConfiguration() throws
}

struct KeychainDiscogsCredentialStore: DiscogsCredentialStoring, Sendable {
    let service: String
    let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "wax.discogs",
        account: String = "discogs.oauth.credentials"
    ) {
        self.service = service
        self.account = account
    }

    func loadCredentials() throws -> DiscogsCredentials? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw DiscogsAuthError.malformedResponse
            }
            return try JSONDecoder().decode(DiscogsCredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError(status: status)
        }
    }

    func saveCredentials(_ credentials: DiscogsCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError(status: addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError(status: status)
        }
    }

    func clearCredentials() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainDiscogsAuthConfigurationStore: DiscogsAuthConfigurationStoring, Sendable {
    let service: String
    let account: String

    init(
        service: String = Bundle.main.bundleIdentifier ?? "wax.discogs",
        account: String = "discogs.oauth.configuration"
    ) {
        self.service = service
        self.account = account
    }

    func loadConfiguration() throws -> PersistedDiscogsAuthConfiguration? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw DiscogsAuthError.malformedResponse
            }
            return try JSONDecoder().decode(PersistedDiscogsAuthConfiguration.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainStoreError(status: status)
        }
    }

    func saveConfiguration(_ configuration: PersistedDiscogsAuthConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        var query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainStoreError(status: addStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError(status: status)
        }
    }

    func clearConfiguration() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError(status: status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct KeychainStoreError: LocalizedError, Sendable {
    let status: OSStatus

    var errorDescription: String? {
        "Keychain operation failed with status \(status)."
    }
}

@MainActor
final class DiscogsAuthStore: ObservableObject {
    enum Readiness: Equatable {
        case unavailable(reason: String)
        case ready(callbackURL: String)
    }

    enum SessionState: Equatable {
        case unavailable
        case signedOut
        case authorizing
        case signedIn(username: String)
    }

    @Published private(set) var sessionState: SessionState = .signedOut
    @Published private(set) var credentials: DiscogsCredentials?
    @Published var errorMessage: String?
    @Published private(set) var readiness: Readiness

    private let authClient: (any DiscogsOAuthClienting)?
    private let credentialStore: any DiscogsCredentialStoring
    private var didRestoreSession = false

    init(
        authClient: (any DiscogsOAuthClienting)?,
        credentialStore: any DiscogsCredentialStoring
    ) {
        self.authClient = authClient
        self.credentialStore = credentialStore
        if let authClient {
            readiness = .ready(callbackURL: authClient.configuration.callbackURL.absoluteString)
        } else {
            readiness = .unavailable(
                reason: "Missing Discogs OAuth consumer key/secret in the current scheme."
            )
            sessionState = .unavailable
        }
    }

    func restoreSession() async {
        guard !didRestoreSession else {
            return
        }

        didRestoreSession = true

        guard authClient != nil else {
            sessionState = .unavailable
            return
        }

        do {
            if let credentials = try credentialStore.loadCredentials() {
                self.credentials = credentials
                sessionState = .signedIn(username: credentials.username)
            } else {
                sessionState = .signedOut
            }
            errorMessage = nil
        } catch {
            sessionState = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signIn(
        authenticateWith presenter: @escaping @MainActor @Sendable (URL, String) async throws -> URL
    ) async {
        guard let authClient else {
            sessionState = .unavailable
            errorMessage = DiscogsAuthError.missingConfiguration.localizedDescription
            return
        }

        do {
            sessionState = .authorizing
            errorMessage = nil

            let requestToken = try await authClient.requestToken()
            let callbackURL = try await presenter(
                requestToken.authorizationURL,
                authClient.configuration.callbackScheme
            )
            var credentials = try await authClient.exchangeAccessToken(
                requestToken: requestToken,
                callbackURL: callbackURL
            )

            if credentials.username.isEmpty {
                let identity = try await authClient.fetchIdentity(credentials: credentials)
                credentials = DiscogsCredentials(
                    oauthToken: credentials.oauthToken,
                    oauthTokenSecret: credentials.oauthTokenSecret,
                    username: identity.username
                )
            }

            try credentialStore.saveCredentials(credentials)
            self.credentials = credentials
            sessionState = .signedIn(username: credentials.username)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            sessionState = .signedOut
            errorMessage = DiscogsAuthError.cancelled.localizedDescription
        } catch {
            sessionState = .signedOut
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try credentialStore.clearCredentials()
            credentials = nil
            errorMessage = nil
            sessionState = authClient == nil ? .unavailable : .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var readinessMessage: String {
        switch readiness {
        case let .ready(callbackURL):
            return "Discogs OAuth ready. Callback: \(callbackURL)"
        case let .unavailable(reason):
            return reason
        }
    }
}

private struct DiscogsIdentityPayload: Decodable {
    let username: String
}

private enum FormEncodedParser {
    static func parse(_ data: Data) throws -> [String: String] {
        guard let body = String(data: data, encoding: .utf8) else {
            throw DiscogsAuthError.malformedResponse
        }

        return body
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, pair in
                let components = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard let key = components.first?.removingPercentEncoding else { return }
                let value = components.count > 1 ? components[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? "" : ""
                result[key] = value
            }
    }
}

enum OAuth1Signer {
    static func authorizationHeader(
        method: String,
        url: URL,
        consumerKey: String,
        consumerSecret: String,
        token: String?,
        tokenSecret: String?,
        additionalOAuthParameters: [String: String] = [:]
    ) -> String {
        let oauthParameters = oauthParameters(
            consumerKey: consumerKey,
            token: token,
            additionalOAuthParameters: additionalOAuthParameters
        )
        let signature = signature(
            method: method,
            url: url,
            consumerSecret: consumerSecret,
            tokenSecret: tokenSecret,
            oauthParameters: oauthParameters
        )

        let headerParameters = oauthParameters.merging(["oauth_signature": signature]) { _, newValue in newValue }
        let headerValue = headerParameters
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\"\(percentEncode(value))\""
            }
            .joined(separator: ", ")

        return "OAuth " + headerValue
    }

    private static func oauthParameters(
        consumerKey: String,
        token: String?,
        additionalOAuthParameters: [String: String]
    ) -> [String: String] {
        var parameters: [String: String] = [
            "oauth_consumer_key": consumerKey,
            "oauth_nonce": UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(Date().timeIntervalSince1970)),
            "oauth_version": "1.0"
        ]

        if let token {
            parameters["oauth_token"] = token
        }

        for (key, value) in additionalOAuthParameters {
            parameters[key] = value
        }

        return parameters
    }

    private static func signature(
        method: String,
        url: URL,
        consumerSecret: String,
        tokenSecret: String?,
        oauthParameters: [String: String]
    ) -> String {
        let normalizedURL = normalizedURL(from: url)
        let queryParameters = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var allParameters = oauthParameters
        for queryParameter in queryParameters {
            allParameters[queryParameter.name] = queryParameter.value ?? ""
        }

        let encodedParameters = allParameters
            .map { key, value in
                (percentEncode(key), percentEncode(value))
            }
        let sortedParameters = encodedParameters.sorted { lhs, rhs in
                lhs.0 == rhs.0 ? lhs.1 < rhs.1 : lhs.0 < rhs.0
            }
        let parameterString = sortedParameters
            .map { "\($0)=\($1)" }
            .joined(separator: "&")

        let baseString = [
            method.uppercased(),
            percentEncode(normalizedURL.absoluteString),
            percentEncode(parameterString)
        ].joined(separator: "&")

        let signingKey = [
            percentEncode(consumerSecret),
            percentEncode(tokenSecret ?? "")
        ].joined(separator: "&")

        let key = SymmetricKey(data: Data(signingKey.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(baseString.utf8),
            using: key
        )
        return Data(signature).base64EncodedString()
    }

    private static func normalizedURL(from url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.query = nil
        components.fragment = nil
        return components.url!
    }

    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private extension URL {
    func oauthQueryValue(named name: String) -> String? {
        URLComponents(url: self, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
