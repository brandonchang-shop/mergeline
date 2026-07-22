import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: DashStore
    @State private var expandPRs = false
    @State private var expandReview = false
    @State private var expandMerged = false
    @State private var newTask = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var showSettings = false
    @State private var showTodoList = false

    private let topN = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsInline(store: store)
            } else if showTodoList {
                VStack(alignment: .leading, spacing: 0) {
                    todoSection
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let msg = store.ghState.message {
                        ghBanner(msg); sectionDivider
                    } else {
                        if store.settings.showOpenPRs { prSection; sectionDivider }
                        if store.settings.showReviewRequests { reviewSection; sectionDivider }
                        if store.settings.showMerged { mergedSection; sectionDivider }
                    }
                    utilitiesSection
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: header / footer
    private var header: some View {
        HStack(spacing: 6) {
            if showSettings || showTodoList {
                Button { withAnimation(.easeInOut(duration: 0.12)) { showSettings = false; showTodoList = false } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }.buttonStyle(.plain)
                Text(showSettings ? "Settings" : "Todo").font(.system(size: 13, weight: .bold))
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                Text("Mergeline").font(.system(size: 14, weight: .heavy))
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    // Shown when the `gh` CLI is missing or not signed in, so lists aren't just blank.
    private func ghBanner(_ msg: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(.orange).frame(width: 15)
            Text(msg).font(.system(size: 11)).foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    // MARK: Utilities (grouped rows, like the Shopify menu-bar app)
    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("UTILITIES", "wrench.and.screwdriver")
            utilityRow("Todo", icon: "checklist", tint: .blue, badge: store.todos.filter { !$0.done }.count) {
                withAnimation(.easeInOut(duration: 0.12)) { showTodoList = true }
            }
            utilityRow("Settings", icon: "gearshape", tint: .secondary) {
                withAnimation(.easeInOut(duration: 0.12)) { showSettings = true }
            }
        }
    }

    private func utilityRow(_ title: String, icon: String, tint: Color, badge: Int = 0, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint).frame(width: 16)
                Text(title).font(.system(size: 12))
                Spacer()
                if badge > 0 {
                    Text("\(badge)").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }.buttonStyle(HoverRow())
    }

    // MARK: PRs
    private var prSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("OPEN PRS", "arrow.triangle.branch")
            if store.openPRs.isEmpty {
                emptyRow(store.loading ? "Loading…" : "No open PRs")
            } else {
                let shown = expandPRs ? store.openPRs : Array(store.openPRs.prefix(topN))
                ForEach(shown) { pr in prRow(pr) }
                if store.openPRs.count > topN {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expandPRs.toggle() }
                    } label: {
                        Label(expandPRs ? "Show less" : "\(store.openPRs.count - topN) more",
                              systemImage: expandPRs ? "chevron.up" : "chevron.down")
                            .font(.caption).foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func prRow(_ pr: PR) -> some View {
        PRRow(pr: pr, onOpen: { open(pr.url) })
    }

    // MARK: Review requests
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("REVIEW REQUESTS", "eye")
            if store.reviewPRs.isEmpty {
                emptyRow(store.loading ? "Loading…" : "No review requests")
            } else {
                let shown = expandReview ? store.reviewPRs : Array(store.reviewPRs.prefix(topN))
                ForEach(shown) { pr in prRow(pr) }
                moreToggle(total: store.reviewPRs.count, expanded: $expandReview)
            }
        }
    }

    // MARK: Merged
    private var mergedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("MERGED · LAST \(store.settings.recentDays) DAY\(store.settings.recentDays == 1 ? "" : "S")", "checkmark.seal.fill")
            if store.mergedPRs.isEmpty {
                emptyRow(store.loading ? "Loading…" : "Nothing merged")
            } else {
                let shown = expandMerged ? store.mergedPRs : Array(store.mergedPRs.prefix(topN))
                ForEach(shown) { pr in prRow(pr) }
                moreToggle(total: store.mergedPRs.count, expanded: $expandMerged)
            }
        }
    }

    // Shared "N more / Show less" toggle (matches Open PRs).
    @ViewBuilder
    private func moreToggle(total: Int, expanded: Binding<Bool>) -> some View {
        if total > topN {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() }
            } label: {
                Label(expanded.wrappedValue ? "Show less" : "\(total - topN) more",
                      systemImage: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(.caption).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
    }

    // MARK: Todos
    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("TODO", "checklist")
            ForEach(store.todos) { todo in todoRow(todo) }
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 12)).foregroundStyle(.blue)
                TextField("Add task…", text: $newTask)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .onSubmit { store.addTodo(newTask); newTask = "" }
            }
            if store.todos.contains(where: { $0.done }) {
                Button { store.clearCompleted() } label: {
                    Label("Clear completed", systemImage: "trash").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
            }
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Button { store.toggle(todo) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(todo.done ? .green : .secondary)
            }.buttonStyle(.plain)

            if editingID == todo.id {
                TextField("", text: $editText, axis: .vertical)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .lineLimit(1...10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { store.edit(todo, to: editText); editingID = nil }
                Button { store.edit(todo, to: editText); editingID = nil } label: {
                    Image(systemName: "checkmark").font(.system(size: 10)).foregroundStyle(.green)
                }.buttonStyle(.plain)
            } else {
                Text(todo.text)
                    .font(.system(size: 12))
                    .strikethrough(todo.done)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { editingID = todo.id; editText = todo.text } label: {
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).opacity(0.7)
                Button { store.delete(todo) } label: {
                    Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(.secondary)
                }.buttonStyle(.plain).opacity(0.7)
            }
        }
    }

    // MARK: helpers
    private func sectionLabel(_ t: String, _ icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(t).font(.system(size: 10, weight: .bold)).tracking(0.8)
        }
        .foregroundStyle(.secondary)
        .padding(.bottom, 2)
    }
    private func emptyRow(_ t: String) -> some View {
        Text(t).font(.system(size: 11)).foregroundStyle(.secondary)
    }
    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}

/// A PR row: click title to open, hover to reveal a copy-URL icon on the right.
struct PRRow: View {
    let pr: PR
    let onOpen: () -> Void
    @State private var hover = false
    @State private var copied = false

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: pr.symbol).font(.system(size: 12)).foregroundStyle(pr.color).frame(width: 15)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(pr.title).lineLimit(1).font(.system(size: 12))
                        Text(pr.repo).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if pr.humanCount > 0 {
                        Text("💬 \(pr.humanCount)").font(.system(size: 10))
                            .help("\(pr.humanCount) open human comment thread\(pr.humanCount == 1 ? "" : "s")")
                    }
                    if pr.botCount > 0 {
                        Text("🤖 \(pr.botCount)").font(.system(size: 10))
                            .help("\(pr.botCount) open bot comment thread\(pr.botCount == 1 ? "" : "s")")
                    }
                }
                .contentShape(Rectangle())
            }.buttonStyle(.plain)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .opacity(hover || copied ? 1 : 0)
            .help("Copy URL")
        }
        .padding(.vertical, 1).padding(.horizontal, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
        .onHover { hover = $0 }
        .contextMenu {
            Button("Open in Browser", action: onOpen)
            Button("Copy URL", action: copy)
        }
    }
}

/// Row style with a subtle hover highlight.
struct HoverRow: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 1).padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Color.primary.opacity(0.08) : .clear))
            .onHover { hover = $0 }
    }
}

// MARK: - Settings (inline section within the popover)

struct SettingsInline: View {
    @ObservedObject var store: DashStore
    @ObservedObject var settings: Settings

    init(store: DashStore) {
        self.store = store
        self.settings = store.settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader("SECTIONS")
            card {
                toggleRow("Open PRs", $settings.showOpenPRs)
                rowDivider
                toggleRow("Review requests", $settings.showReviewRequests)
                rowDivider
                toggleRow("Merged", $settings.showMerged)
            }

            groupHeader("DATA")
            card {
                HStack(spacing: 6) {
                    Text("Recent window").font(.system(size: 12))
                    Spacer()
                    TextField("", value: $settings.recentDays, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 42)
                        .onSubmit {
                            settings.recentDays = min(max(settings.recentDays, 1), 365)
                            store.refresh()
                        }
                    Text("day\(settings.recentDays == 1 ? "" : "s")")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Stepper("", value: $settings.recentDays, in: 1...365)
                        .labelsHidden()
                        .onChange(of: settings.recentDays) { _, _ in store.refresh() }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }

            groupHeader("REVIEW REQUESTS")
            card {
                toggleRow("Include team requests", $settings.includeTeamReviews)
                    .onChange(of: settings.includeTeamReviews) { _, _ in store.refresh() }
            }
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func groupHeader(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(0.8)
            .foregroundStyle(.secondary).padding(.leading, 4)
    }
    private var rowDivider: some View { Divider().padding(.leading, 10) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
    private func toggleRow(_ title: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: binding).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }
}

