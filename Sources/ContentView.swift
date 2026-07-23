import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: DashStore
    @State private var expandPRs = false
    @State private var expandReview = false
    @State private var expandMention = false
    @State private var expandMerged = false
    @State private var showSettings = false
    @State private var showLegend = false
    @State private var showNotifs = false

    private let topN = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsInline(store: store)
            } else if showLegend {
                ScrollView {
                    legendScreen
                        .padding(.leading, 12).padding(.trailing, 20).padding(.vertical, 10)
                }
                .frame(maxHeight: 460)
                .scrollIndicators(.visible)
            } else if showNotifs {
                notifsScreen
                    .padding(.horizontal, 12).padding(.vertical, 10)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if let msg = store.ghState.message {
                        ghBanner(msg); sectionDivider
                    } else {
                        if store.settings.showOpenPRs { prSection; sectionDivider }
                        if store.settings.showReviewRequests { reviewSection; sectionDivider }
                        if store.settings.showMentions { mentionSection; sectionDivider }
                        if store.settings.showMerged { mergedSection; sectionDivider }
                    }
                    utilitiesSection
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
        }
        .frame(width: 370)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: header / footer
    private var header: some View {
        HStack(spacing: 6) {
            if showSettings || showLegend || showNotifs {
                Button { withAnimation(.easeInOut(duration: 0.12)) { showSettings = false; showLegend = false; showNotifs = false } } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                        Text("Back").font(.system(size: 13, weight: .semibold))
                    }
                }.buttonStyle(HoverRow())
                Spacer()
                Text(showSettings ? "Settings" : showLegend ? "Legend" : "Notifications").font(.system(size: 13, weight: .bold))
            } else {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                Text("Mergeline").font(.system(size: 14, weight: .heavy))
                Spacer()
                bellButton
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 10)
    }

    private var sectionDivider: some View {
        Divider().padding(.vertical, 8)
    }

    // Bell + unread badge (header, main screen only). Opening marks all read.
    private var bellButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { showNotifs = true }
            store.markAllRead()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: store.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(store.unreadCount > 0 ? Color.primary : Color.secondary)
                if store.unreadCount > 0 {
                    Text("\(min(store.unreadCount, 99))")
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 8, y: -7)
                }
            }
        }.buttonStyle(HoverRow())
    }

    // MARK: Notifications (in-app activity feed)
    private var notifsScreen: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.notifications.isEmpty {
                Text("No new activity").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
            } else {
                HStack {
                    groupHeaderText("RECENT ACTIVITY")
                    Spacer()
                    Button("Clear") { store.clearNotifications() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ScrollView {
                    card {
                        ForEach(Array(store.notifications.enumerated()), id: \.element.id) { i, n in
                            if i > 0 { rowDividerInset }
                            HStack(spacing: 0) {
                                Button { open(n.url) } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: changeIcon(n.change)).font(.system(size: 12))
                                            .foregroundStyle(changeColor(n.change)).frame(width: 16)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(n.title).font(.system(size: 12)).lineLimit(1)
                                            Text("\(n.change) · \(n.repo)").font(.system(size: 10))
                                                .foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer(minLength: 6)
                                        Text(DashStore.relativeTime(n.at)).font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.leading, 10).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }.buttonStyle(HoverRow())
                                Button { store.dismissNotification(n.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary).frame(width: 26, height: 26)
                                        .contentShape(Rectangle())
                                }.buttonStyle(HoverRow()).help("Dismiss")
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
                .scrollIndicators(.visible)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func changeIcon(_ c: String) -> String {
        if c.hasPrefix("Approved") { return "checkmark.seal.fill" }
        if c.hasPrefix("Changes")  { return "xmark.octagon.fill" }
        if c.hasPrefix("CI failed") { return "exclamationmark.triangle.fill" }
        if c == "Merged" { return "arrow.triangle.merge" }
        if c == "New pull request" { return "plus.circle" }
        if c.contains("bot") { return "cpu" }
        return "bubble.left.fill"
    }
    private func changeColor(_ c: String) -> Color {
        if c.hasPrefix("Approved") || c == "Merged" { return .green }
        if c.hasPrefix("Changes")  { return .red }
        if c.hasPrefix("CI failed") { return .orange }
        return .secondary
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
            utilityRow("Legend", icon: "questionmark.circle", tint: .secondary) {
                withAnimation(.easeInOut(duration: 0.12)) { showLegend = true }
            }
            utilityRow("Settings", icon: "gearshape", tint: .secondary) {
                withAnimation(.easeInOut(duration: 0.12)) { showSettings = true }
            }
        }
    }

    // MARK: Legend (what the icons mean)
    private var legendScreen: some View {
        VStack(alignment: .leading, spacing: 14) {
            legendGroup("PR STATUS", [
                ("arrow.triangle.branch", Color.secondary, "Open — no review/CI signal yet"),
                ("clock.fill", .yellow, "CI checks running"),
                ("exclamationmark.triangle.fill", .orange, "CI checks failing"),
                ("xmark.octagon.fill", .red, "Changes requested"),
                ("checkmark.seal.fill", .green, "Approved"),
                ("pencil.circle", .secondary, "Draft"),
                ("arrow.triangle.merge", .green, "Merged"),
            ])
            legendGroupEmoji("PR COMMENTS", [
                ("💬", "Open threads from people"),
                ("🤖", "Open threads from bots (binks, orc, CI)"),
            ])
            legendGroup("NOTIFICATIONS", [
                ("plus.circle", .secondary, "A new pull request appeared"),
                ("bubble.left.fill", .secondary, "New comment on a PR"),
                ("cpu", .secondary, "New bot comment"),
                ("checkmark.seal.fill", .green, "A PR was approved"),
                ("xmark.octagon.fill", .red, "Changes were requested"),
                ("exclamationmark.triangle.fill", .orange, "CI started failing"),
                ("arrow.triangle.merge", .green, "A PR was merged"),
            ])
            legendGroupEmoji("SECTIONS", [
                ("@", "Open PRs where you're @mentioned"),
            ])
            legendGroupEmoji("ROW ACTIONS", [
                ("🖱", "Click a PR to open it in the browser"),
                ("★", "Star to pin (sorts to top of section)"),
                ("⎘", "Hover a row → copy-URL icon on the right"),
                ("✕", "Dismiss one notification (Clear = all)"),
            ])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendGroup(_ title: String, _ rows: [(String, Color, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeaderText(title)
            card {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { rowDividerInset }
                    HStack(spacing: 10) {
                        Image(systemName: r.0).font(.system(size: 12)).foregroundStyle(r.1).frame(width: 18)
                        Text(r.2).font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
        }
    }

    private func legendGroupEmoji(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupHeaderText(title)
            card {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { rowDividerInset }
                    HStack(spacing: 10) {
                        Text(r.0).font(.system(size: 13)).frame(width: 18)
                        Text(r.1).font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
            }
        }
    }

    private func groupHeaderText(_ t: String) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(0.8)
            .foregroundStyle(.secondary).padding(.leading, 4)
    }
    private var rowDividerInset: some View { Divider().padding(.leading, 10) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
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
                emptyRow(store.loading && !store.hasLoaded ? "Loading…" : "No open PRs")
            } else {
                prList(store.openPRs, expanded: $expandPRs)
            }
        }
    }

    private func prRow(_ pr: PR) -> some View {
        PRRow(pr: pr,
              onOpen: { open(pr.url) },
              isPinned: store.pinnedURLs.contains(pr.url),
              onTogglePin: { withAnimation(.easeInOut(duration: 0.15)) { store.togglePin(pr.url) } })
    }

    // MARK: Review requests
    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("REVIEW REQUESTS", "eye")
            if store.reviewPRs.isEmpty {
                emptyRow(store.loading && !store.hasLoaded ? "Loading…" : "No review requests")
            } else {
                prList(store.reviewPRs, expanded: $expandReview)
            }
        }
    }

    // MARK: Mentions
    private var mentionSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("MENTIONS", "at")
            if store.mentionPRs.isEmpty {
                emptyRow(store.loading && !store.hasLoaded ? "Loading…" : "No mentions")
            } else {
                prList(store.mentionPRs, expanded: $expandMention)
            }
        }
    }

    // MARK: Merged
    private var mergedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("MERGED · LAST \(store.settings.recentDays) DAY\(store.settings.recentDays == 1 ? "" : "S")", "checkmark.seal.fill")
            if store.mergedPRs.isEmpty {
                emptyRow(store.loading && !store.hasLoaded ? "Loading…" : "Nothing merged")
            } else {
                prList(store.mergedPRs, expanded: $expandMerged)
            }
        }
    }

    // Shared PR list. Collapsed = top N. Expanded = all rows, but if the list is
    // long the SECTION scrolls (capped height) instead of growing the whole window.
    @ViewBuilder
    private func prList(_ prs: [PR], expanded: Binding<Bool>) -> some View {
        // Pinned PRs float to the top of the section (stable order within each group).
        let pinned = prs.filter { store.pinnedURLs.contains($0.url) }
        let rest = prs.filter { !store.pinnedURLs.contains($0.url) }
        let ordered = pinned + rest
        let shown = expanded.wrappedValue ? ordered : Array(ordered.prefix(topN))
        if expanded.wrappedValue && ordered.count > 5 {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shown) { pr in prRow(pr) }
                }
                // Reserve a constant gutter so the scrollbar (thin or hover-expanded)
                // always sits here and never overlaps the star/copy icons or shifts rows.
                .padding(.trailing, 16)
            }
            .scrollIndicators(.visible)
            .frame(maxHeight: 170)
        } else {
            ForEach(shown) { pr in prRow(pr) }
        }
        moreToggle(total: prs.count, expanded: expanded)
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
        // Only open https github.com links (URLs come from the API; guard against
        // an unexpected scheme/host being handed to the system opener).
        guard let u = URL(string: url), u.scheme == "https",
              (u.host == "github.com" || (u.host?.hasSuffix(".github.com") ?? false))
        else { return }
        NSWorkspace.shared.open(u)
    }
}

/// A PR row: click title to open, hover to reveal a copy-URL icon on the right.
struct PRRow: View {
    let pr: PR
    let onOpen: () -> Void
    var isPinned: Bool = false
    var onTogglePin: () -> Void = {}
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

            Button(action: onTogglePin) {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(isPinned ? Color.yellow : Color.secondary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
            .opacity(isPinned || hover ? 1 : 0)
            .help(isPinned ? "Unpin" : "Pin")

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
        .contentShape(Rectangle())   // make the whole row (incl. gaps) hoverable
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
    @State private var daysText: String

    init(store: DashStore) {
        self.store = store
        self.settings = store.settings
        _daysText = State(initialValue: String(store.settings.recentDays))
    }

    private func commitDays() {
        let n = min(max(Int(daysText) ?? settings.recentDays, 1), 365)
        settings.recentDays = n
        daysText = String(n)
        store.refresh()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            groupHeader("SECTIONS")
            card {
                toggleRow("Open PRs", $settings.showOpenPRs)
                rowDivider
                toggleRow("Review requests", $settings.showReviewRequests)
                rowDivider
                toggleRow("Mentions", $settings.showMentions)
                rowDivider
                toggleRow("Merged", $settings.showMerged)
            }

            groupHeader("DATA")
            card {
                HStack(spacing: 8) {
                    Text("Recent window").font(.system(size: 12))
                    Spacer()
                    // Editable "N days" pill that blends with the card styling.
                    HStack(spacing: 3) {
                        TextField("", text: $daysText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .multilineTextAlignment(.trailing)
                            .frame(width: 26)
                            // Keep only digits as the user types.
                            .onChange(of: daysText) { _, v in
                                let digits = v.filter(\.isNumber)
                                if digits != v { daysText = digits }
                            }
                            .onSubmit { commitDays() }
                        Text((Int(daysText) ?? settings.recentDays) == 1 ? "day" : "days")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    Stepper("", value: $settings.recentDays, in: 1...365)
                        .labelsHidden()
                        .controlSize(.small)
                        .onChange(of: settings.recentDays) { _, v in daysText = String(v); store.refresh() }
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
        .frame(width: 370, alignment: .leading)
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

