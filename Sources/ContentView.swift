import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: DashStore
    @State private var expandPRs = false
    @State private var newTask = ""
    @State private var editingID: UUID?
    @State private var editText = ""
    @State private var showSettings = false

    private let topN = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsInline(store: store)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if store.settings.showOpenPRs { prSection; sectionDivider }
                    if store.settings.showMerged { mergedSection; sectionDivider }
                    if store.settings.showTodos { todoSection; sectionDivider }
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
            if showSettings {
                Button { withAnimation(.easeInOut(duration: 0.12)) { showSettings = false } } label: {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                }.buttonStyle(.plain)
                Text("Settings").font(.system(size: 13, weight: .bold))
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                Text("Dev Dashboard").font(.system(size: 13, weight: .bold))
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    // MARK: Utilities (grouped rows, like the Shopify menu-bar app)
    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("UTILITIES", "wrench.and.screwdriver")
            utilityRow("Generate standup", icon: "sparkles", tint: .purple) {
                store.generateStandup(); StandupWindowController.show(store: store)
            }
            utilityRow("Settings", icon: "gearshape", tint: .secondary) {
                withAnimation(.easeInOut(duration: 0.12)) { showSettings = true }
            }
        }
    }

    private func utilityRow(_ title: String, icon: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 12)).foregroundStyle(tint).frame(width: 16)
                Text(title).font(.system(size: 12))
                Spacer()
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
        Button { open(pr.url) } label: {
            HStack(spacing: 8) {
                Image(systemName: pr.symbol).font(.system(size: 12)).foregroundStyle(pr.color).frame(width: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.title).lineLimit(1).font(.system(size: 12))
                    Text(pr.repo).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }.buttonStyle(HoverRow())
    }

    // MARK: Merged
    private var mergedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("MERGED · LAST \(store.settings.recentDays) DAY\(store.settings.recentDays == 1 ? "" : "S")", "checkmark.seal.fill")
            if store.mergedPRs.isEmpty {
                emptyRow("Nothing merged")
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
                    Text(store.standupText ?? "")
                        .font(.system(size: 13, design: .monospaced))
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
    @State private var launch: Bool

    init(store: DashStore) {
        self.store = store
        self.settings = store.settings
        _launch = State(initialValue: store.settings.launchAtLogin)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader("SECTIONS")
            card {
                toggleRow("Open PRs", $settings.showOpenPRs)
                rowDivider
                toggleRow("Merged", $settings.showMerged)
                rowDivider
                toggleRow("Todo", $settings.showTodos)
            }

            groupHeader("DATA")
            card {
                HStack {
                    Text("Recent window").font(.system(size: 12))
                    Spacer()
                    Stepper("\(settings.recentDays) day\(settings.recentDays == 1 ? "" : "s")",
                            value: $settings.recentDays, in: 1...90)
                        .font(.system(size: 12))
                        .onChange(of: settings.recentDays) { _, _ in store.refresh() }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }

            groupHeader("GENERAL")
            card {
                toggleRow("Launch at login", $launch)
                    .onChange(of: launch) { _, v in settings.launchAtLogin = v }
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
