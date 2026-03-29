import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var problems: [Problem] = []
    @State private var searchText = ""
    @State private var page = 0
    @State private var hasMore = true
    @State private var isSearching = false
    private let pageSize = 20

    let onSelect: (Problem) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.background.ignoresSafeArea()

                Group {
                    if problems.isEmpty && !isSearching {
                        emptyState
                    } else {
                        List {
                            ForEach(problems) { problem in
                                HistoryRow(problem: problem)
                                    .listRowBackground(Theme.Colors.secondaryBackground)
                                    .listRowSeparator(.hidden)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        Haptics.light()
                                        onSelect(problem)
                                        dismiss()
                                    }
                            }
                            .onDelete(perform: deleteProblem)

                            if hasMore && searchText.isEmpty {
                                ProgressView()
                                    .tint(Theme.Colors.accent)
                                    .frame(maxWidth: .infinity)
                                    .listRowBackground(Color.clear)
                                    .onAppear { loadNextPage() }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .searchable(text: $searchText, prompt: "Search problems...")
                        .onChange(of: searchText) { _, newValue in
                            if newValue.isEmpty {
                                resetAndLoad()
                            } else {
                                searchProblems(newValue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
            .onAppear {
                if problems.isEmpty {
                    loadNextPage()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadNextPage() {
        var descriptor = FetchDescriptor<Problem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = pageSize
        descriptor.fetchOffset = page * pageSize

        do {
            let results = try modelContext.fetch(descriptor)
            problems.append(contentsOf: results)
            hasMore = results.count == pageSize
            page += 1
        } catch {
            hasMore = false
        }
    }

    private func resetAndLoad() {
        problems.removeAll()
        page = 0
        hasMore = true
        isSearching = false
        loadNextPage()
    }

    private func searchProblems(_ query: String) {
        isSearching = true
        var descriptor = FetchDescriptor<Problem>(
            predicate: #Predicate<Problem> {
                $0.text.localizedStandardContains(query) ||
                $0.topic.localizedStandardContains(query)
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50

        do {
            problems = try modelContext.fetch(descriptor)
            hasMore = false
        } catch {
            problems = []
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.base) {
            Image(systemName: "camera")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary)

            Text("Your solved problems will appear here")
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func deleteProblem(at offsets: IndexSet) {
        for index in offsets {
            let problem = problems[index]
            modelContext.delete(problem)
            problems.remove(at: index)
        }
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let problem: Problem

    var body: some View {
        HStack(spacing: 14) {
            if let imageData = problem.sourceImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.Colors.accentSubtle)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "function")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Colors.accent.opacity(0.5))
                    )
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(problem.text)
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)

                Text(problem.createdAt, style: .relative)
                    .font(Theme.Fonts.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 6)
    }
}
