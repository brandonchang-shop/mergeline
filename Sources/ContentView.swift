import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: DashStore
    @State private var expandPRs = false
    @State private var newTask = ""
    @State private var editingID: UUID?
    @State private var editText = ""

    private let topN = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.settings.showOpenPRs { prSection }
                    if store.settings.showMerged { mergedSection }
                    if store.settings.showTodos { todoSection }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(width: 330, height: 440)
    }

    // MARK: header / footer
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 12)).foregroundStyle(.primary)
            Text("Dev Dashboard").font(.system(size: 12, weight: .semibold))
            Spacer()
            if store.loading { ProgressView().controlSize(.small).scaleEffect(0.7) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Button { store.refresh() } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Button { store.generateStandup(); StandupWindowController.show(store: store) } label: {
                Label("Standup", systemImage: "sparkles")
            }.buttonStyle(.plain).foregroundStyle(Color.purple)
            Button { SettingsWindowController.show(store: store) } label: {
                Image(systemName: "gearshape")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            if !store.updated.isEmpty {
                Text("Updated \(store.updated)").font(.caption).foregroundStyle(.secondary)
            }
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power")
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    // MARK: PRs
    private var prSection: some View {
        VStack(alignment: .leading, spacing: 3) {
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
            HStack(spacing: 6) {
                Image(systemName: pr.symbol).font(.system(size: 11)).foregroundStyle(pr.color).frame(width: 13)
                VStack(alignment: .leading, spacing: 0) {
                    Text(pr.title).lineLimit(1).font(.system(size: 11))
                    Text(pr.repo).font(.system(size: 9)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }.buttonStyle(HoverRow())
    }

    // MARK: Merged
    private var mergedSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("MERGED · LAST 7 DAYS", "checkmark.seal.fill")
            if store.mergedPRs.isEmpty {
                emptyRow("Nothing merged")
            } else {
                ForEach(store.mergedPRs.prefix(topN)) { pr in prRow(pr) }
            }
        }
    }

    // MARK: Todos
    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            sectionLabel("TODO", "checklist")
            ForEach(store.todos) { todo in todoRow(todo) }
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundStyle(.blue)
                TextField("Add task…", text: $newTask)
                    .textFieldStyle(.plain).font(.system(size: 11))
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
                    .font(.system(size: 11))
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
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(t).font(.system(size: 9, weight: .semibold)).tracking(0.5)
        }.foregroundStyle(.secondary)
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

// MARK: - Settings

struct SettingsView: View {
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
            Text("Settings").font(.headline)
            Divider()

            Text("SECTIONS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Toggle("Open PRs", isOn: $settings.showOpenPRs)
            Toggle("Merged · recent", isOn: $settings.showMerged)
            Toggle("Todo", isOn: $settings.showTodos)

            Divider()
            HStack {
                Text("Recent window")
                Spacer()
                Stepper("\(settings.recentDays) day\(settings.recentDays == 1 ? "" : "s")",
                        value: $settings.recentDays, in: 1...90)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Repo filter (comma-separated, blank = all)")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("e.g. data-warehouse, skai-train", text: $settings.repoFilter)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()
            Toggle("Launch at login", isOn: $launch)
                .onChange(of: launch) { _, v in settings.launchAtLogin = v }

            Spacer()
            HStack {
                Spacer()
                Button("Apply & Refresh") { store.refresh() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 320, height: 380)
    }
}

enum SettingsWindowController {
    static var window: NSWindow?
    static func show(store: DashStore) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "DevDash Settings"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: SettingsView(store: store))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
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
