import CryptoKit
import Foundation

enum DiscogsCollectionImportError: LocalizedError, Sendable {
    case malformedResponse
    case invalidHTTPStatus(Int)

    var errorDescription: String? {
        switch self {
        case .malformedResponse:
            return "Discogs collection response was malformed."
        case let .invalidHTTPStatus(statusCode):
            return "Discogs collection request failed with status \(statusCode)."
        }
    }
}

protocol DiscogsCollectionAPIClienting: Sendable {
    func fetchCollectionReleases(
        username: String,
        credentials: DiscogsCredentials,
        page: Int,
        perPage: Int
    ) async throws -> DiscogsCollectionPage
}

struct DiscogsCollectionAPIClient: DiscogsCollectionAPIClienting, Sendable {
    let configuration: DiscogsAuthConfiguration
    let networking: any DiscogsNetworking

    init(
        configuration: DiscogsAuthConfiguration,
        networking: any DiscogsNetworking = URLSession.shared
    ) {
        self.configuration = configuration
        self.networking = networking
    }

    func fetchCollectionReleases(
        username: String,
        credentials: DiscogsCredentials,
        page: Int,
        perPage: Int
    ) async throws -> DiscogsCollectionPage {
        var components = URLComponents(string: "https://api.discogs.com/users/\(username)/collection/folders/0/releases")!
        components.queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sort", value: "added"),
            URLQueryItem(name: "sort_order", value: "desc")
        ]

        let endpoint = components.url!
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

        let (data, response) = try await networking.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DiscogsCollectionImportError.malformedResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw DiscogsCollectionImportError.invalidHTTPStatus(httpResponse.statusCode)
        }

        return try JSONDecoder.discogsCollectionDecoder.decode(DiscogsCollectionPage.self, from: data)
    }
}

protocol DiscogsCollectionImporting: Sendable {
    func importCollection(username: String, credentials: DiscogsCredentials) async throws -> Int
}

struct DiscogsCollectionImporter: DiscogsCollectionImporting, Sendable {
    let apiClient: any DiscogsCollectionAPIClienting
    let recordRepository: any RecordRepository
    let collectionRepository: any CollectionRepository
    let imageAssetRepository: any ImageAssetRepository
    let checkpointRepository: any SyncCheckpointRepository

    func importCollection(username: String, credentials: DiscogsCredentials) async throws -> Int {
        let pageSize = 100
        var importedCount = 0
        var page = 1
        var totalPages = 1

        repeat {
            let payload = try await apiClient.fetchCollectionReleases(
                username: username,
                credentials: credentials,
                page: page,
                perPage: pageSize
            )

            for (index, release) in payload.releases.enumerated() {
                try await importRelease(
                    release,
                    sortPosition: ((page - 1) * pageSize) + index
                )
                importedCount += 1
            }

            totalPages = payload.pagination.pages
            page += 1
        } while page <= totalPages

        let timestamp = Date()
        let checkpoint = SyncCheckpoint(
            scope: .collectionBootstrap,
            cursor: "page-\(max(totalPages, 1))",
            lastSyncedAt: timestamp,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try await checkpointRepository.save(checkpoint)

        return importedCount
    }

    private func importRelease(
        _ release: DiscogsCollectionRelease,
        sortPosition: Int
    ) async throws {
        let timestamp = release.dateAdded ?? Date()
        let recordID = UUID.discogsScoped("record:\(release.basicInformation.id)")
        let existingRecord = try await recordRepository.fetchRecord(discogsID: release.basicInformation.id)
        let title = release.basicInformation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artistNames = release.basicInformation.artists.map(\.name).joined(separator: ", ")

        let record = Record(
            id: existingRecord?.id ?? recordID,
            discogsID: release.basicInformation.id,
            title: title,
            artist: artistNames.isEmpty ? "Unknown Artist" : artistNames,
            year: release.basicInformation.year,
            format: release.basicInformation.displayFormat,
            notes: existingRecord?.notes ?? "",
            condition: existingRecord?.condition,
            syncStatus: .synced,
            createdAt: existingRecord?.createdAt ?? timestamp,
            updatedAt: timestamp
        )
        try await recordRepository.upsert(record)

        let entryID = UUID.discogsScoped("collection-entry:\(release.instanceID)")
        let entry = CollectionEntry(
            id: entryID,
            recordID: record.id,
            discogsInstanceID: release.instanceID,
            folderID: release.folderID,
            dateAdded: release.dateAdded,
            sortPosition: sortPosition,
            syncStatus: .synced,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        try await collectionRepository.upsert(entry)

        if let coverImage = release.basicInformation.coverImageURL {
            let asset = ImageAsset(
                id: UUID.discogsScoped("image-asset:\(release.basicInformation.id)"),
                recordID: record.id,
                discogsImageURL: coverImage,
                createdAt: timestamp,
                updatedAt: timestamp
            )
            try await imageAssetRepository.upsert(asset)
        }
    }
}

struct DiscogsCollectionPage: Decodable, Sendable {
    let pagination: DiscogsPagination
    let releases: [DiscogsCollectionRelease]
}

struct DiscogsPagination: Decodable, Sendable {
    let page: Int
    let pages: Int
    let perPage: Int
    let items: Int

    private enum CodingKeys: String, CodingKey {
        case page
        case pages
        case perPage = "per_page"
        case items
    }
}

struct DiscogsCollectionRelease: Decodable, Sendable {
    let instanceID: Int
    let folderID: Int?
    let dateAdded: Date?
    let basicInformation: DiscogsBasicInformation

    private enum CodingKeys: String, CodingKey {
        case instanceID = "instance_id"
        case folderID = "folder_id"
        case dateAdded = "date_added"
        case basicInformation = "basic_information"
    }
}

struct DiscogsBasicInformation: Decodable, Sendable {
    let id: Int
    let title: String
    let year: Int?
    let coverImageURL: URL?
    let artists: [DiscogsArtist]
    let formats: [DiscogsFormat]

    var displayFormat: String? {
        let values = formats.flatMap { format -> [String] in
            var items = [format.name]
            items.append(contentsOf: format.descriptions ?? [])
            return items
        }
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case coverImageURL = "cover_image"
        case artists
        case formats
    }
}

struct DiscogsArtist: Decodable, Sendable {
    let name: String
}

struct DiscogsFormat: Decodable, Sendable {
    let name: String
    let descriptions: [String]?
}

private extension JSONDecoder {
    static var discogsCollectionDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let value = DatabaseDateCodec.decode(string) {
                return value
            }
            throw DiscogsCollectionImportError.malformedResponse
        }
        return decoder
    }
}

private extension UUID {
    static func discogsScoped(_ value: String) -> UUID {
        let digest = SHA256.hash(data: Data(value.utf8))
        let bytes = Array(digest.prefix(16))
        let tuple = (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )
        return UUID(uuid: tuple)
    }
}
