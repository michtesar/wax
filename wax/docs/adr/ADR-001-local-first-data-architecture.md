# ADR-001: Local-First Data Architecture

## Status

Accepted

## Date

2026-03-23

## Context

`wax` is building a local-first record collection app with Discogs integration, offline edits, background sync, and a SwiftUI UI that should render from local state without blocking on network requests.

The current project scaffold still contains default `SwiftData` template wiring, but the product requirements call for:

- predictable SQLite storage with explicit schema and migrations
- sync queue semantics and conflict handling
- repository-driven reads and writes
- clear separation between Discogs-synced fields and local-only fields

## Decisions

### Database

Use `GRDB + SQLite` as the persistence stack.

Why:

- explicit schema, migrations, indexes, and SQL-level performance tuning
- better fit for sync queues, checkpoints, and background processing than template-oriented `SwiftData`
- easier to reason about incremental sync, retries, and repair operations

`Core Data` is rejected for the MVP because it adds framework complexity without improving the local-first sync model enough to justify it here.

### Sync Scope

Sync to Discogs:

- collection membership
- Discogs-linked metadata that maps cleanly to collection entries
- condition, when Discogs API support and account permissions allow it

Keep local-only:

- notes
- cached images
- sync telemetry
- UI-only state and local performance indexes

If Discogs condition support proves partial or inconsistent, the app will still keep a local condition field and treat remote condition sync as best-effort capability behind the sync engine.

### Identity

Use:

- `Record.id` as app-local `UUID`
- `discogsID` as nullable external identifier with a unique index when present

Rationale:

- local UUID enables optimistic creation before remote identity exists
- unique Discogs identity prevents duplicate imports during bootstrap and incremental sync
- local and remote identity stay decoupled, which simplifies manual entries and conflict recovery

## Consequences

### Positive

- app can read and write fully offline from day one
- migrations and indexing are explicit
- sync queue and checkpoint tables can be modeled directly
- future performance tuning is easier at the query level

### Negative

- requires adding and maintaining a third-party dependency (`GRDB`)
- more persistence code must be written manually than with `SwiftData`
- repository and migration coverage become mandatory

## Implementation Notes

- remove default `SwiftData` container wiring from the app scaffold
- introduce `DatabaseManager`, migrations, and repository protocols in D1
- model remote-facing sync state explicitly instead of deriving it from UI state

## Follow-up

D1 should produce:

- schema for `Record`, `CollectionEntry`, `SyncOperation`, `SyncCheckpoint`, and `ImageAsset`
- migration plan with forward-only migrations and development seed helpers
- repository interfaces for local-first reads and optimistic writes
