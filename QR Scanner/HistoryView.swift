import SwiftUI
import SwiftData
import UIKit

private enum DateFilter: String, CaseIterable, Identifiable {
    case all, day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Time"
        case .day: return "Last 24 Hours"
        case .week: return "Last 7 Days"
        case .month: return "Last 30 Days"
        }
    }

    var cutoffDate: Date? {
        switch self {
        case .all:
            return nil
        case .day:
            return Calendar.current.date(byAdding: .day, value: -1, to: Date())
        case .week:
            return Calendar.current.date(byAdding: .day, value: -7, to: Date())
        case .month:
            return Calendar.current.date(byAdding: .day, value: -30, to: Date())
        }
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \ScanRecord.createdAt, order: .reverse) private var scans: [ScanRecord]
    @State private var searchText = ""
    @State private var selectedKindRaw: String? = nil
    @State private var dateFilter: DateFilter = .all
    @State private var favoritesOnly: Bool = false

    @State private var showClearConfirm = false
    @State private var showShare = false
    @State private var shareText: String = ""

    @State private var selection = Set<ObjectIdentifier>()
    @State private var editMode: EditMode = .inactive

    private var kindOptions: [String] {
        Array(Set(scans.map { $0.kindRaw })).sorted()
    }

    var filtered: [ScanRecord] {
        var result = scans

        if let kind = selectedKindRaw, kindOptions.contains(kind) {
            result = result.filter { $0.kindRaw == kind }
        }

        if favoritesOnly {
            result = result.filter { $0.isFavorite }
        }

        if let cutoff = dateFilter.cutoffDate {
            result = result.filter { $0.createdAt >= cutoff }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { $0.rawValue.localizedCaseInsensitiveContains(query) }
        }

        return result
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if filtered.isEmpty {
                    ContentUnavailableView("No scans yet", systemImage: "clock")
                } else {
                    ForEach(filtered) { scan in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(scan.kindRaw.uppercased())
                                if scan.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(scan.rawValue)
                                .lineLimit(2)
                                .font(.body)

                            Text(scan.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .tag(ObjectIdentifier(scan))
                        .onLongPressGesture {
                            editMode = .active
                            selection.insert(ObjectIdentifier(scan))
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                UIPasteboard.general.string = scan.rawValue
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                            .tint(.blue)

                            if let url = ScanParser.parse(scan.rawValue).normalizedURL {
                                Button {
                                    openURL(url)
                                } label: {
                                    Label("Open", systemImage: "safari")
                                }
                                .tint(.green)
                            }

                            Button {
                                shareText = scan.rawValue
                                showShare = true
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                scan.isFavorite.toggle()
                            } label: {
                                Label(scan.isFavorite ? "Unfavorite" : "Favorite", systemImage: scan.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            modelContext.delete(filtered[i])
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(scans.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode == .active && !selection.isEmpty {
                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle(isOn: $favoritesOnly) {
                            Label("Favorites only", systemImage: favoritesOnly ? "star.fill" : "star")
                        }

                        Divider()

                        Picker("Kind", selection: $selectedKindRaw) {
                            Text("All").tag(nil as String?)
                            ForEach(kindOptions, id: \.self) { kind in
                                Text(kind.uppercased()).tag(kind as String?)
                            }
                        }
                        Picker("Date", selection: $dateFilter) {
                            ForEach(DateFilter.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItemGroup(placement: .bottomBar) {
                    if editMode == .active {
                        Text(selection.isEmpty ? "Select items" : "\(selection.count) selected")
                            .foregroundStyle(.secondary)
                        Spacer()

                        Button {
                            copySelected()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(selection.isEmpty)

                        Button {
                            shareSelected()
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(selection.isEmpty)

                        Button(role: .destructive) {
                            deleteSelected()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selection.isEmpty)
                    }
                }
            }
            .confirmationDialog("Delete all history?", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("Delete All", role: .destructive) {
                    for s in scans { modelContext.delete(s) }
                }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showShare) {
                ActivityView(activityItems: [shareText])
            }
            .environment(\.editMode, $editMode)
        }
    }

    private var selectedRecords: [ScanRecord] {
        let ids = selection
        return scans.filter { ids.contains(ObjectIdentifier($0)) }
    }

    private func copySelected() {
        let lines = selectedRecords.map { $0.rawValue }
        UIPasteboard.general.string = lines.joined(separator: "\n")
    }

    private func shareSelected() {
        let lines = selectedRecords.map { $0.rawValue }
        shareText = lines.joined(separator: "\n")
        showShare = true
    }

    private func deleteSelected() {
        let ids = selection
        for scan in scans {
            if ids.contains(ObjectIdentifier(scan)) {
                modelContext.delete(scan)
            }
        }
        selection.removeAll()
    }
}
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

