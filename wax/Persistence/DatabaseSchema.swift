import Foundation

struct DatabaseMigration: Identifiable, Hashable, Sendable {
    let id: String
    let statements: [String]
}

enum DatabaseSchema {
    static let migrations: [DatabaseMigration] = [
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

    static let developmentSeedStatements: [String] = [
        """
        INSERT INTO sync_checkpoint (
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
        """
    ]

    static let rollbackStrategy = """
    Rollback policy:
    - production uses forward-only migrations
    - failed startup migration aborts database open and surfaces a fatal persistence error
    - development reset drops the SQLite file and reapplies all migrations plus development seeds
    - no destructive down migrations are shipped for user data
    """
}
