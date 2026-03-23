import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @ObservedObject var store: CollectionStore
    @State private var gridColumns = 2
    @State private var selectedFilter: CollectionFilter = .all
    @State private var searchPresented = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: CrateSpacing.m), count: gridColumns)
    }

    private var filteredRecords: [Record] {
        switch selectedFilter {
        case .all:
            return store.records
        case .recent:
            return store.records.sorted { $0.createdAt > $1.createdAt }.prefix(6).map(\.self)
        case .needsSync:
            return store.records.filter { $0.syncStatus != .synced }
        }
    }

    private var syncedCount: Int {
        store.records.filter { $0.syncStatus == .synced }.count
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                CrateColor.background.ignoresSafeArea()
                CrateBackgroundGlow()

                ScrollView {
                    VStack(spacing: CrateSpacing.l) {
                        Color.clear.frame(height: 88)
                        if let bootstrapStatusMessage = store.bootstrapStatusMessage {
                            BootstrapModeBanner(message: bootstrapStatusMessage)
                                .padding(.horizontal, CrateSpacing.l)
                        }
                        FilterPills(selected: $selectedFilter)
                            .padding(.horizontal, CrateSpacing.l)
                        if filteredRecords.isEmpty, store.hasLoaded {
                            EmptyCollectionView(
                                isFiltered: selectedFilter != .all,
                                hasError: store.errorMessage != nil
                            )
                            .padding(.horizontal, CrateSpacing.l)
                        } else {
                            LazyVGrid(columns: columns, spacing: CrateSpacing.l) {
                                ForEach(filteredRecords) { record in
                                    NavigationLink {
                                        RecordDetailView(record: record)
                                    } label: {
                                        ArtworkCard(record: record)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, CrateSpacing.l)
                            .padding(.bottom, 140)
                        }
                    }
                }
                .gesture(
                    MagnificationGesture()
                        .onEnded { value in
                            updateGridDensity(for: value)
                        }
                )

                GlassTopBar(
                    title: "Collection",
                    totalCount: store.records.count,
                    syncedCount: syncedCount,
                    onSearchTap: { searchPresented = true }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                AddRecordButton()
                    .padding(.trailing, CrateSpacing.l)
                    .padding(.bottom, CrateSpacing.xxl)
            }
            .sheet(isPresented: $searchPresented) {
                SearchSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .modifier(HideNavigationBarOnIOS())
            .task {
                await store.bootstrap()
            }
            .refreshable {
                await store.reload()
            }
        }
    }

    private func updateGridDensity(for scale: CGFloat) {
        let previous = gridColumns
        if scale > 1.18 {
            gridColumns = max(2, gridColumns - 1)
        } else if scale < 0.88 {
            gridColumns = min(4, gridColumns + 1)
        }
        if previous != gridColumns {
            Haptics.light()
        }
    }
}

private enum CollectionFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case recent = "Recently Added"
    case needsSync = "Needs Sync"

    var id: String { rawValue }
}

private enum CrateColor {
    static let background = Color(hex: "0B0B0C")
    static let primary = Color(hex: "F5F5F7")
    static let secondary = Color(hex: "A1A1AA")
    static let accent = Color(hex: "C6A27E")
    static let success = Color(hex: "32D74B")
}

private enum CrateSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

private struct CrateBackgroundGlow: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.10))
                .blur(radius: 70)
                .frame(width: 220)
                .offset(x: -120, y: -260)
            Circle()
                .fill(CrateColor.accent.opacity(0.25))
                .blur(radius: 80)
                .frame(width: 180)
                .offset(x: 120, y: -190)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

private struct GlassTopBar: View {
    let title: String
    let totalCount: Int
    let syncedCount: Int
    let onSearchTap: () -> Void

    var body: some View {
        VStack(spacing: CrateSpacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .foregroundStyle(CrateColor.primary)
                Spacer()
                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CrateColor.primary)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: CrateSpacing.s) {
                Circle()
                    .fill(CrateColor.success)
                    .frame(width: 8, height: 8)
                Text("\(totalCount) records")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CrateColor.secondary)
                Spacer()
                Text("\(syncedCount) synced")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CrateColor.secondary)
            }
        }
        .padding(.horizontal, CrateSpacing.l)
        .padding(.top, 12)
        .padding(.bottom, CrateSpacing.s)
        .background(.ultraThinMaterial.opacity(0.95))
        .background(Color.white.opacity(0.07))
        .overlay(
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }
}

private struct FilterPills: View {
    @Binding var selected: CollectionFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: CrateSpacing.s) {
                ForEach(CollectionFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            selected = filter
                        }
                        Haptics.light()
                    } label: {
                        Text(filter.rawValue)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(selected == filter ? CrateColor.primary : CrateColor.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(selected == filter ? .white.opacity(0.18) : .white.opacity(0.08))
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(.white.opacity(0.12), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct ArtworkCard: View {
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: CrateSpacing.s) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hue: record.artworkHue, saturation: 0.45, brightness: 0.95),
                                Color(hue: record.artworkHue, saturation: 0.55, brightness: 0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.45), lineWidth: 2)
                            .padding(28)
                    )
                    .overlay(
                        Circle()
                            .fill(.black.opacity(0.35))
                            .frame(width: 20, height: 20)
                    )
                if record.syncStatus != .synced {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(CrateColor.primary)
                                .padding(6)
                                .background(.black.opacity(0.35), in: Circle())
                        }
                        Spacer()
                    }
                    .padding(10)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.white.opacity(0.15), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.30), radius: 20, x: 0, y: 8)

            Text(record.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CrateColor.primary)
                .lineLimit(1)
            Text(record.metadataLine)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CrateColor.secondary)
                .lineLimit(1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct AddRecordButton: View {
    var body: some View {
        Button {
            Haptics.medium()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CrateColor.primary)
                .frame(width: 54, height: 54)
                .background(.ultraThinMaterial)
                .background(CrateColor.accent.opacity(0.24))
                .clipShape(Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CrateColor.background.ignoresSafeArea()
                VStack(spacing: CrateSpacing.l) {
                    TextField("Search Discogs", text: .constant(""))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(CrateColor.primary)
                        .padding(CrateSpacing.l)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Text("Local collection search ships first. Discogs lookup comes after sync/auth wiring.")
                        .font(.footnote)
                        .foregroundStyle(CrateColor.secondary)
                    Spacer()
                }
                .padding(CrateSpacing.l)
            }
            .toolbar {
                ToolbarItem(placement: toolbarPlacement) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(CrateColor.accent)
                }
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
#if os(iOS)
        .topBarTrailing
#else
        .automatic
#endif
    }
}

private struct RecordDetailView: View {
    let record: Record

    var body: some View {
        ZStack(alignment: .top) {
            CrateColor.background.ignoresSafeArea()
            CrateBackgroundGlow()
            ScrollView {
                VStack(alignment: .leading, spacing: CrateSpacing.xl) {
                    HeroArtwork(record: record)
                        .padding(.top, 12)
                    VStack(alignment: .leading, spacing: CrateSpacing.s) {
                        Text(record.title)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(CrateColor.primary)
                        Text(record.artist)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(CrateColor.secondary)
                        Text(record.detailLine)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(CrateColor.secondary)
                    }
                    QuickActions()
                    Timeline(record: record)
                }
                .padding(.horizontal, CrateSpacing.l)
                .padding(.bottom, 32)
            }
        }
        .modifier(DetailNavigationStyling())
    }
}

private struct HeroArtwork: View {
    let record: Record

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hue: record.artworkHue, saturation: 0.35, brightness: 1.0),
                            Color(hue: record.artworkHue, saturation: 0.56, brightness: 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .aspectRatio(1, contentMode: .fit)
                .overlay(Circle().stroke(.white.opacity(0.40), lineWidth: 3).padding(34))
                .overlay(Circle().fill(.black.opacity(0.35)).frame(width: 24, height: 24))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(.white.opacity(0.15), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 10)
    }
}

private struct QuickActions: View {
    var body: some View {
        HStack(spacing: CrateSpacing.s) {
            quickButton(title: "Condition", icon: "dial.medium")
            quickButton(title: "Notes", icon: "square.and.pencil")
            quickButton(title: "Discogs", icon: "safari")
        }
    }

    private func quickButton(title: String, icon: String) -> some View {
        Button {
            Haptics.light()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CrateColor.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct Timeline: View {
    let record: Record

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            timelineRow(label: "Added", value: record.createdAt.timelineLabel)
            timelineRow(label: "Updated", value: record.updatedAt.timelineLabel)
            timelineRow(label: "Sync Status", value: record.syncStatus.displayTitle)
        }
        .padding(CrateSpacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        )
    }

    private func timelineRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CrateColor.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CrateColor.primary)
        }
    }
}

private struct BootstrapModeBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: CrateSpacing.s) {
            Image(systemName: "shippingbox")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(CrateColor.accent)
            Text(message)
                .font(.footnote.weight(.medium))
                .foregroundStyle(CrateColor.primary)
            Spacer()
        }
        .padding(.horizontal, CrateSpacing.m)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

private struct EmptyCollectionView: View {
    let isFiltered: Bool
    let hasError: Bool

    var body: some View {
        VStack(spacing: CrateSpacing.m) {
            Image(systemName: hasError ? "exclamationmark.triangle" : "square.stack.3d.up.slash")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(CrateColor.accent)
            Text(hasError ? "Collection unavailable" : (isFiltered ? "No matching records" : "Collection is empty"))
                .font(.headline.weight(.semibold))
                .foregroundStyle(CrateColor.primary)
            Text(hasError ? "Database bootstrap failed. Check the current error state and retry." : "Your local library will appear here as soon as records are stored offline.")
                .font(.footnote)
                .foregroundStyle(CrateColor.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .padding(.horizontal, CrateSpacing.l)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

private enum Haptics {
    static func light() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    static func medium() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)
        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (255, 255, 255)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: 1
        )
    }
}

private struct HideNavigationBarOnIOS: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content.navigationBarHidden(true)
#else
        content
#endif
    }
}

private struct DetailNavigationStyling: ViewModifier {
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
#else
        content
#endif
    }
}

private extension Record {
    var artworkHue: Double {
        Double(abs(title.hashValue ^ artist.hashValue) % 100) / 100
    }

    var metadataLine: String {
        if let year {
            "\(artist) • \(year)"
        } else {
            artist
        }
    }

    var detailLine: String {
        let yearText = year.map(String.init) ?? "Unknown year"
        let conditionText = condition?.rawValue ?? "Unrated"
        return "\(yearText) • Condition \(conditionText)"
    }
}

private extension SyncStatus {
    var displayTitle: String {
        switch self {
        case .pending:
            "Pending"
        case .syncing:
            "Syncing"
        case .synced:
            "Synced"
        case .failed:
            "Failed"
        }
    }
}

private extension Date {
    var timelineLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

#Preview {
    ContentView(store: AppContainer().makeCollectionStore())
        .preferredColorScheme(.dark)
}
