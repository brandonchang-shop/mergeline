import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: DashStore
    @State private var expandPRs = false
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
            utilityRow("Generate standup", icon: "sparkles", tint: .purple) {
                store.generateStandup(); StandupWindowController.show(store: store)
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
                ForEach(store.reviewPRs.prefix(topN)) { pr in prRow(pr) }
                if store.reviewPRs.count > topN {
                    emptyRow("+\(store.reviewPRs.count - topN) more")
                }
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
                ForEach(store.mergedPRs.prefix(topN)) { pr in prRow(pr) }
            }
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

/// Renders the standup as native-font sections: a bold "Header:" line + a paragraph,
/// styled to match the rest of the app (system font, not monospaced).
struct StandupBody: View {
    let text: String
    private let headers = ["Shipped:", "Working on:", "Blockers:"]

    private struct Section: Identifiable { let id = UUID(); let title: String; let body: String }

    private var sections: [Section] {
        var result: [Section] = []
        var current: String? = nil
        var buf: [String] = []
        func flush() {
            if let c = current {
                result.append(Section(title: c, body: buf.joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)))
            }
            buf = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let h = headers.first(where: { line.caseInsensitiveCompare($0) == .orderedSame }) {
                flush(); current = h
            } else if !line.isEmpty {
                buf.append(line)
            }
        }
        flush()
        return result
    }

    var body: some View {
        let secs = sections
        if secs.isEmpty {
            Text(text).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(secs) { s in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.title.replacingOccurrences(of: ":", with: "").uppercased())
                            .font(.system(size: 10, weight: .bold)).tracking(0.8)
                            .foregroundStyle(.secondary)
                        Text(s.body).font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// Standup content shown in a standalone, movable & resizable window.
struct StandupWindowView: View {
    @ObservedObject var store: DashStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.standupLoading {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Generating…").foregroundStyle(.secondary).font(.caption)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    StandupBody(text: store.standupText ?? "")
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider()
            HStack {
                Button {
                    if let t = store.standupText {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(t, forType: .string)
                    }
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(store.standupText == nil)
                Spacer()
                Button { store.generateStandup() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .disabled(store.standupLoading)
            }
        }
        .padding(14)
        .frame(minWidth: 320, minHeight: 220)
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

/// Opens/reuses a real NSWindow (draggable, resizable) for the standup.
enum StandupWindowController {
    static var window: NSWindow?
    static func show(store: DashStore) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered, defer: false)
            w.title = "Standup"
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 320, height: 220)
            w.center()
            w.contentView = NSHostingView(rootView: StandupWindowView(store: store))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
