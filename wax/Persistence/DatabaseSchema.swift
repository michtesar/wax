import Foundation

struct DatabaseMigration: Identifiable, Hashable, Sendable {
    nonisolated let id: String
    nonisolated let statements: [String]
}

enum DatabaseSchema {
    nonisolated static let migrations: [DatabaseMigration] = [
        DatabaseMigration(
            id: "20260323_001_create_record_collection_sync_tables",
            statements: [
                """
                CREATE TABLE IF NOT EXISTS record (
                    id TEXT PRIMARY KEY NOT NULL,
                    discogs_id INTEGER UNIQUE,
                    title TEXT NOT NULL,
                    artist TEXT NOT NULL,
                    year INTEGER,
                    format TEXT,
                    notes TEXT NOT NULL DEFAULT '',
                    condition TEXT,
                    sync_status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS collection_entry (
                    id TEXT PRIMARY KEY NOT NULL,
                    record_id TEXT NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    discogs_instance_id INTEGER UNIQUE,
                    folder_id INTEGER,
                    date_added TEXT,
                    sort_position INTEGER,
                    sync_status TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS sync_operation (
                    id TEXT PRIMARY KEY NOT NULL,
                    entity_type TEXT NOT NULL,
                    entity_id TEXT NOT NULL,
                    operation_type TEXT NOT NULL,
                    payload BLOB,
                    state TEXT NOT NULL,
                    attempt_count INTEGER NOT NULL DEFAULT 0,
                    next_attempt_at TEXT,
                    last_error_message TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS sync_checkpoint (
                    id TEXT PRIMARY KEY NOT NULL,
                    scope TEXT NOT NULL UNIQUE,
                    cursor TEXT,
                    last_synced_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                """
                CREATE TABLE IF NOT EXISTS image_asset (
                    id TEXT PRIMARY KEY NOT NULL,
                    record_id TEXT NOT NULL REFERENCES record(id) ON DELETE CASCADE,
                    discogs_image_url TEXT,
                    thumbnail_local_path TEXT,
                    fullsize_local_path TEXT,
                    pixel_width INTEGER,
                    pixel_height INTEGER,
                    byte_size INTEGER,
                    last_accessed_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                """,
                "CREATE INDEX IF NOT EXISTS idx_record_discogs_id ON record(discogs_id);",
                "CREATE INDEX IF NOT EXISTS idx_record_updated_at ON record(updated_at);",
                "CREATE INDEX IF NOT EXISTS idx_record_sync_status ON record(sync_status);",
                "CREATE INDEX IF NOT EXISTS idx_collection_entry_record_id ON collection_entry(record_id);",
                "CREATE INDEX IF NOT EXISTS idx_collection_entry_updated_at ON collection_entry(updated_at);",
                "CREATE INDEX IF NOT EXISTS idx_collection_entry_sync_status ON collection_entry(sync_status);",
                "CREATE INDEX IF NOT EXISTS idx_sync_operation_state ON sync_operation(state);",
                "CREATE INDEX IF NOT EXISTS idx_sync_operation_next_attempt_at ON sync_operation(next_attempt_at);",
                "CREATE INDEX IF NOT EXISTS idx_sync_operation_updated_at ON sync_operation(updated_at);",
                "CREATE INDEX IF NOT EXISTS idx_image_asset_record_id ON image_asset(record_id);",
                "CREATE INDEX IF NOT EXISTS idx_image_asset_last_accessed_at ON image_asset(last_accessed_at);"
            ]
        )
    ]

    nonisolated static let developmentSeedStatements: [String] = [
        """
        INSERT OR IGNORE INTO sync_checkpoint (
            id,
            scope,
            cursor,
            last_synced_at,
            created_at,
            updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000001',
            'collectionBootstrap',
            NULL,
            NULL,
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
        );
        """,
        """
        INSERT OR IGNORE INTO record (
            id,
            discogs_id,
            title,
            artist,
            year,
            format,
            notes,
            condition,
            sync_status,
            created_at,
            updated_at
        ) VALUES
        (
            '11111111-1111-1111-1111-111111111111',
            249504,
            'Moon Safari',
            'Air',
            1998,
            'LP',
            'Seeded sample record',
            'NM',
            'synced',
            '2026-03-23T10:00:00.000Z',
            '2026-03-23T10:00:00.000Z'
        ),
        (
            '22222222-2222-2222-2222-222222222222',
            91551,
            'Discovery',
            'Daft Punk',
            2001,
            '2xLP',
            '',
            'VG+',
            'pending',
            '2026-03-24T10:00:00.000Z',
            '2026-03-24T10:00:00.000Z'
        ),
        (
            '33333333-3333-3333-3333-333333333333',
            2783,
            'Kind of Blue',
            'Miles Davis',
            1959,
            'LP',
            'Mono pressing',
            'VG',
            'failed',
            '2026-03-25T10:00:00.000Z',
            '2026-03-25T10:00:00.000Z'
        );
        """,
        """
        INSERT OR IGNORE INTO collection_entry (
            id,
            record_id,
            discogs_instance_id,
            folder_id,
            date_added,
            sort_position,
            sync_status,
            created_at,
            updated_at
        ) VALUES
        (
            'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            '11111111-1111-1111-1111-111111111111',
            501,
            1,
            '2026-03-23T10:00:00.000Z',
            1,
            'synced',
            '2026-03-23T10:00:00.000Z',
            '2026-03-23T10:00:00.000Z'
        ),
        (
            'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
            '22222222-2222-2222-2222-222222222222',
            502,
            1,
            '2026-03-24T10:00:00.000Z',
            2,
            'pending',
            '2026-03-24T10:00:00.000Z',
            '2026-03-24T10:00:00.000Z'
        ),
        (
            'cccccccc-cccc-cccc-cccc-cccccccccccc',
            '33333333-3333-3333-3333-333333333333',
            503,
            1,
            '2026-03-25T10:00:00.000Z',
            3,
            'failed',
            '2026-03-25T10:00:00.000Z',
            '2026-03-25T10:00:00.000Z'
        );
        """
    ]

    nonisolated static let rollbackStrategy = """
    Rollback policy:
    - production uses forward-only migrations
    - failed startup migration aborts database open and surfaces a fatal persistence error
    - development reset drops the SQLite file and reapplies all migrations plus development seeds
    - no destructive down migrations are shipped for user data
    """
}
