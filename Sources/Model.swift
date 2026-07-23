import AppKit
import SwiftUI
import ServiceManagement
import Combine

// MARK: - Data types

struct PR: Identifiable, Codable {
    var id: String { url }
    let repo: String
    let title: String
    let url: String
    var status: String = "neutral"   // neutral|merged|approved|fail|pending|changes|draft
    var humanCount: Int = 0          // unresolved review threads opened by a human
    var botCount: Int = 0            // unresolved review threads opened by a bot (binks/orc/etc.)

    init(repo: String, title: String, url: String, status: String = "neutral",
         humanCount: Int = 0, botCount: Int = 0) {
        self.repo = repo; self.title = title; self.url = url
        self.status = status; self.humanCount = humanCount; self.botCount = botCount
    }

    // Tolerate old cache files that lack the newer fields.
    enum CodingKeys: String, CodingKey { case repo, title, url, status, humanCount, botCount }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        repo = try c.decode(String.self, forKey: .repo)
        title = try c.decode(String.self, forKey: .title)
        url = try c.decode(String.self, forKey: .url)
        status = (try? c.decode(String.self, forKey: .status)) ?? "neutral"
        humanCount = (try? c.decode(Int.self, forKey: .humanCount)) ?? 0
        botCount = (try? c.decode(Int.self, forKey: .botCount)) ?? 0
    }

    var symbol: String {
        switch status {
        case "merged":   return "arrow.triangle.merge"
        case "approved": return "checkmark.seal.fill"
        case "fail":     return "exclamationmark.triangle.fill"
        case "pending":  return "clock.fill"
        case "changes":  return "xmark.octagon.fill"
        case "draft":    return "pencil.circle"
        default:          return "arrow.triangle.branch"
        }
    }
    var color: Color {
        switch status {
        case "merged", "approved": return .green
        case "fail":               return .orange
        case "pending":            return .yellow
        case "changes":            return .red
        default:                    return .secondary
        }
    }
}

// MARK: - Settings (persisted in UserDefaults)

final class Settings: ObservableObject {
    private let d = UserDefaults.standard
    // Read with a fallback so a missing key defaults to the intended value
    // (avoids the "everything false" bug where stored-property init runs before register()).
    private static func boolOr(_ key: String, _ def: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)
    }
    private static func intOr(_ key: String, _ def: Int) -> Int {
        UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.integer(forKey: key)
    }

    @Published var showOpenPRs = Settings.boolOr("showOpenPRs", true) {
        didSet { d.set(showOpenPRs, forKey: "showOpenPRs") }
    }
    @Published var showMerged = Settings.boolOr("showMerged", true) {
        didSet { d.set(showMerged, forKey: "showMerged") }
    }
    @Published var showReviewRequests = Settings.boolOr("showReviewRequests", true) {
        didSet { d.set(showReviewRequests, forKey: "showReviewRequests") }
    }
    @Published var showMentions = Settings.boolOr("showMentions", true) {
        didSet { d.set(showMentions, forKey: "showMentions") }
    }
    // When false (default), Review Requests shows only PRs requested from you
    // directly; when true, also includes ones requested via your teams.
    @Published var includeTeamReviews = Settings.boolOr("includeTeamReviews", false) {
        didSet { d.set(includeTeamReviews, forKey: "includeTeamReviews") }
    }
    @Published var recentDays = max(1, Settings.intOr("recentDays", 7)) {
        didSet { d.set(recentDays, forKey: "recentDays") }
    }

    // Launch at login (SMAppService, macOS 13+)
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register()
                          : try SMAppService.mainApp.unregister() }
            catch { NSLog("launchAtLogin toggle failed: \(error)") }
            objectWillChange.send()
        }
    }
}

// MARK: - Shell helper

enum Shell {
    static let extraPath = [
        "\(NSHomeDirectory())/.local/state/tec/toolchain/base_profile/bin",
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
    ].joined(separator: ":")

    /// An empty scratch dir used as the working directory for child processes.
    /// When launched via `open`, the app's cwd is `/`; tools like `claude` scan
    /// their cwd as a "project", and walking from `/` reaches TCC-protected user
    /// folders (Photos/Music) → spurious permission prompts. Running in an empty
    /// dir gives them nothing protected to scan.
    static let workDir: String = {
        let dir = "\(NSHomeDirectory())/.pi/mergeline_work"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    @discardableResult
    static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: workDir)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = extraPath + ":" + (env["PATH"] ?? "")
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Notifications (in-app activity feed)

/// A minimal per-PR snapshot used to diff successive fetches.
struct PRSnap: Codable { let status: String; let human: Int; let bot: Int }

/// One "something changed" entry shown in the bell dropdown.
struct Notif: Codable, Identifiable {
    let id: String            // url + change, so identical repeats collapse
    let url, title, repo, change: String
    let at: Date
    var read: Bool
}

// MARK: - Cache (open instantly with last data)

private struct Cache: Codable {
    var open: [PR]
    var merged: [PR]
    var review: [PR]? = nil
    var mention: [PR]? = nil
    var updated: String
    var snapshot: [String: PRSnap]? = nil   // baseline for change detection
    var notifs: [Notif]? = nil              // in-app activity feed
}

// MARK: - Store

/// Health of the `gh` CLI dependency, so the UI can show a clear message
/// instead of silently-empty lists.
enum GHState: Equatable {
    case ok
    case notAuthed   // gh installed but `gh auth status` fails
    case missing     // gh not on PATH

    var message: String? {
        switch self {
        case .ok:        return nil
        case .notAuthed: return "GitHub CLI isn't signed in. Run `gh auth login` in a terminal, then reopen."
        case .missing:   return "GitHub CLI (gh) not found. Install it and run `gh auth login`."
        }
    }
}

final class DashStore: ObservableObject {
    @Published var openPRs: [PR] = []
    @Published var mergedPRs: [PR] = []
    @Published var reviewPRs: [PR] = []
    @Published var mentionPRs: [PR] = []
    @Published var loading = false
    // True once at least one fetch (or a cache load) has populated the sections.
    // Used so empty sections show "No X" instead of spinning "Loading…" during
    // every background refresh — only the very first load shows "Loading…".
    @Published var hasLoaded = false
    // Locally pinned PR URLs (persisted). Pinned rows sort to the top of their section.
    @Published var pinnedURLs: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "pinnedPRURLs") ?? [])
    func togglePin(_ url: String) {
        if pinnedURLs.contains(url) { pinnedURLs.remove(url) } else { pinnedURLs.insert(url) }
        UserDefaults.standard.set(Array(pinnedURLs), forKey: "pinnedPRURLs")
    }
    @Published var ghState: GHState = .ok
    private var pendingRefresh = false
    @Published var updated = ""
    // In-app activity feed (bell dropdown). `snapshot` is the last-seen per-PR
    // state used to diff each fetch; both persist in the cache.
    @Published var notifications: [Notif] = []
    var unreadCount: Int { notifications.reduce(0) { $0 + ($1.read ? 0 : 1) } }
    private var snapshot: [String: PRSnap] = [:]

    let settings = Settings()
    private let cachePath = "\(NSHomeDirectory())/.pi/mergeline_cache.json"
    private let cacheQueue = DispatchQueue(label: "io.local.mergeline.cache", qos: .utility)
    // Cached login (never changes). Persisted to UserDefaults so cold launches
    // skip the extra `gh api user` round-trip before the batched query.
    private var viewerLogin = UserDefaults.standard.string(forKey: "viewerLogin") ?? ""
    private var cancellables = Set<AnyCancellable>()

    init() {
        loadCache()   // show last-known PRs immediately, before gh runs
        // Re-publish settings changes so views watching the store re-render
        // (e.g. toggling a section updates the main view instantly).
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // ---- Cache ----
    private func loadCache() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: cachePath)),
              let c = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        openPRs = c.open; mergedPRs = c.merged; reviewPRs = c.review ?? []; mentionPRs = c.mention ?? []; updated = c.updated
        notifications = c.notifs ?? []
        snapshot = c.snapshot ?? [:]
        hasLoaded = true   // we have prior data; don't show first-load spinner
    }
    private func saveCache() {
        // Snapshot on the main thread, then encode + write off it (disk I/O can
        // stall on slow/encrypted/network home dirs). 0600 keeps PR titles/URLs
        // private on shared machines.
        let c = Cache(open: openPRs, merged: mergedPRs, review: reviewPRs, mention: mentionPRs,
                      updated: updated, snapshot: snapshot, notifs: notifications)
        let path = cachePath
        cacheQueue.async {
            guard let data = try? JSONEncoder().encode(c) else { return }
            try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }

    // ---- Refresh PRs (background) ----
    func refresh() {
        // If a refresh is already running, don't drop this request — remember it
        // and re-run once the current one finishes (picks up the latest settings,
        // e.g. a changed recent-days window).
        if loading { pendingRefresh = true; return }
        loading = true
        let since = Self.daysAgo(settings.recentDays)
        let includeTeam = settings.includeTeamReviews

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let gh = Self.checkGH()
            DispatchQueue.main.async { self.ghState = gh }
            guard gh == .ok else {
                DispatchQueue.main.async {
                    self.loading = false
                    if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
                }
                return
            }

            // ONE batched GraphQL request fetches all four sections *and* their
            // per-PR status + comment counts in a single network round-trip
            // (previously ~4 searches + up to 6×2 enrichment calls per section).
            let login = self.login()
            let sections = self.fetchAll(login: login, since: since, includeTeam: includeTeam)

            DispatchQueue.main.async {
                // On a failed fetch (e.g. GitHub rate limit → nil), KEEP the last
                // good data and cache instead of blanking the UI.
                if let sections {
                    self.openPRs = sections.open
                    self.mergedPRs = sections.merged
                    self.reviewPRs = sections.review
                    // Drop mention PRs already shown in Open PRs or Review Requests
                    // so a PR doesn't appear in two sections at once.
                    let seen = Set(sections.open.map(\.url)).union(sections.review.map(\.url))
                    self.mentionPRs = sections.mention.filter { !seen.contains($0.url) }
                    self.detectChanges(self.openPRs + self.reviewPRs + self.mentionPRs + self.mergedPRs)
                    self.updated = Self.timeStamp()
                    self.hasLoaded = true
                    self.saveCache()
                }
                self.loading = false
                if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
            }
        }
    }

    // ---- Change detection / notifications ----
    /// Diffs the fresh PR set against the last snapshot and appends notifications
    /// for anything that changed. First run only records the baseline (no spam).
    private func detectChanges(_ prs: [PR]) {
        let firstRun = snapshot.isEmpty
        var newSnap: [String: PRSnap] = [:]
        var events: [Notif] = []
        for pr in prs {
            if newSnap[pr.url] != nil { continue }   // a url can appear in 2 sections
            let ns = PRSnap(status: pr.status, human: pr.humanCount, bot: pr.botCount)
            let old = snapshot[pr.url]
            newSnap[pr.url] = ns
            guard !firstRun, let change = Self.changeString(old: old, new: ns) else { continue }
            events.append(Notif(id: "\(pr.url)#\(change)", url: pr.url, title: pr.title,
                                repo: pr.repo, change: change, at: Date(), read: false))
        }
        snapshot = newSnap
        guard !events.isEmpty else { return }
        // Prepend, collapse identical (url+change) repeats, cap at 50.
        var seen = Set<String>()
        notifications = Array((events + notifications).filter { seen.insert($0.id).inserted }.prefix(50))
    }

    /// Human-readable description of what changed, or nil if nothing notable.
    static func changeString(old: PRSnap?, new: PRSnap) -> String? {
        guard let old else { return new.status == "merged" ? nil : "New pull request" }
        if new.status != old.status {
            switch new.status {
            case "merged":   return "Merged"
            case "approved": return "Approved"
            case "changes":  return "Changes requested"
            case "fail":     return "CI failed"
            default: break   // pending/neutral/draft transitions aren't worth a notif
            }
        }
        if new.human > old.human {
            let d = new.human - old.human
            return "\(d) new comment\(d == 1 ? "" : "s")"
        }
        if new.bot > old.bot {
            let d = new.bot - old.bot
            return "\(d) new bot comment\(d == 1 ? "" : "s")"
        }
        return nil
    }

    func markAllRead() {
        guard notifications.contains(where: { !$0.read }) else { return }
        notifications = notifications.map { var n = $0; n.read = true; return n }
        saveCache()
    }
    func clearNotifications() { notifications = []; saveCache() }
    func dismissNotification(_ id: String) { notifications.removeAll { $0.id == id }; saveCache() }

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated; return f
    }()
    static func relativeTime(_ d: Date) -> String { relFormatter.localizedString(for: d, relativeTo: Date()) }

    /// Detect whether `gh` is installed and authenticated.
    private static func checkGH() -> GHState {
        if Shell.run(["gh", "--version"]).isEmpty { return .missing }
        // `gh auth token` prints a token to stdout only when authenticated.
        return Shell.run(["gh", "auth", "token"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .notAuthed : .ok
    }

    /// The authenticated user's login (GraphQL search needs the literal name,
    /// not gh's `@me` shorthand). Fetched once and cached for the session.
    private func login() -> String {
        if Self.isValidLogin(viewerLogin) { return viewerLogin }
        let out = Shell.run(["gh", "api", "user", "--jq", ".login"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidLogin(out) else { return "" }   // don't trust/interpolate garbage
        viewerLogin = out
        UserDefaults.standard.set(out, forKey: "viewerLogin")
        return out
    }

    /// GitHub usernames: 1–39 chars, alphanumerics + single hyphens, no leading/
    /// trailing hyphen. Validated before interpolating into search queries (also
    /// rejects a tampered UserDefaults `viewerLogin`).
    private static func isValidLogin(_ s: String) -> Bool {
        guard (1...39).contains(s.count), !s.hasPrefix("-"), !s.hasSuffix("-") else { return false }
        let allowed = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return s.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Fetches all four sections in a single GraphQL call. Each `search` alias
    /// pulls the PR list plus the fields needed for status + 💬/🤖 counts, so
    /// no follow-up per-PR requests are required.
    /// Returns nil on failure (empty login, network error, or a GraphQL error
    /// such as rate limiting) so the caller can preserve the last good data.
    private func fetchAll(login: String, since: String, includeTeam: Bool)
        -> (open: [PR], merged: [PR], review: [PR], mention: [PR])? {
        guard !login.isEmpty else { return nil }

        let openQ    = "author:\(login) is:pr is:open sort:updated-desc"
        let mergedQ  = "author:\(login) is:pr is:merged merged:>=\(since) sort:updated-desc"
        let reviewQ  = includeTeam
            ? "review-requested:\(login) is:pr is:open sort:updated-desc"
            : "user-review-requested:\(login) is:pr is:open sort:updated-desc"
        let mentionQ = "mentions:\(login) is:pr is:open sort:updated-desc"

        // Reusable PR field set. `reviews(last:30)` lets us derive approval even
        // when `reviewDecision` is null (repos without required reviews).
        let prFields = """
          ... on PullRequest {
            title url isDraft reviewDecision
            repository { name }
            commits(last:1){ nodes { commit { statusCheckRollup { state } } } }
            reviews(last:10, states:[APPROVED, CHANGES_REQUESTED]){ nodes { state author { login } } }
            reviewThreads(first:30){ nodes {
              isResolved
              comments(first:1){ nodes { author { login __typename } } }
            }}
          }
        """
        let query = """
        query($openQ:String!,$mergedQ:String!,$reviewQ:String!,$mentionQ:String!){
          open:search(query:$openQ,type:ISSUE,first:20){ nodes { \(prFields) } }
          merged:search(query:$mergedQ,type:ISSUE,first:20){ nodes { \(prFields) } }
          review:search(query:$reviewQ,type:ISSUE,first:20){ nodes { \(prFields) } }
          mention:search(query:$mentionQ,type:ISSUE,first:20){ nodes { \(prFields) } }
        }
        """

        let out = Shell.run(["gh", "api", "graphql",
                             "-f", "query=\(query)",
                             "-f", "openQ=\(openQ)",
                             "-f", "mergedQ=\(mergedQ)",
                             "-f", "reviewQ=\(reviewQ)",
                             "-f", "mentionQ=\(mentionQ)"])
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        // A GraphQL error (e.g. RATE_LIMITED) returns an `errors` array; treat as
        // failure so we don't blank the UI with empty sections.
        if obj["errors"] != nil { return nil }
        guard let root = obj["data"] as? [String: Any] else { return nil }

        func parse(_ alias: String, merged: Bool) -> [PR] {
            guard let sec = root[alias] as? [String: Any],
                  let nodes = sec["nodes"] as? [[String: Any]] else { return [] }
            return nodes.compactMap { Self.pr(from: $0, merged: merged) }
        }
        return (parse("open", merged: false),
                parse("merged", merged: true),
                parse("review", merged: false),
                parse("mention", merged: false))
    }

    /// Builds a PR (with status + comment counts) from one GraphQL search node.
    private static func pr(from node: [String: Any], merged: Bool) -> PR? {
        let url = node["url"] as? String ?? ""
        guard !url.isEmpty else { return nil }   // skip non-PR nodes (issues)
        let title = node["title"] as? String ?? ""
        let repo = (node["repository"] as? [String: Any])?["name"] as? String ?? ""

        var pr = PR(repo: repo, title: title, url: url)
        if merged {
            pr.status = "merged"
            return pr
        }

        // ---- status ----
        if node["isDraft"] as? Bool == true {
            pr.status = "draft"
        } else {
            // reviewDecision is null unless reviews are required; fall back to the
            // latest review state per author.
            var review = (node["reviewDecision"] as? String)?.uppercased() ?? ""
            // `reviewDecision` is only conclusive as APPROVED / CHANGES_REQUESTED.
            // For "" (repos without required reviews) OR REVIEW_REQUIRED (protected
            // repo, reviews still pending), derive from the actual review states so
            // a requested-changes review isn't shown as neutral.
            if review != "APPROVED", review != "CHANGES_REQUESTED",
               let nodes = (node["reviews"] as? [String: Any])?["nodes"] as? [[String: Any]] {
                var latest: [String: String] = [:]   // author login -> last APPROVED/CHANGES_REQUESTED
                for r in nodes {
                    let st = (r["state"] as? String ?? "").uppercased()
                    guard st == "APPROVED" || st == "CHANGES_REQUESTED" else { continue }
                    let who = ((r["author"] as? [String: Any])?["login"] as? String) ?? ""
                    latest[who] = st
                }
                let states = Set(latest.values)
                if states.contains("CHANGES_REQUESTED") { review = "CHANGES_REQUESTED" }
                else if states.contains("APPROVED") { review = "APPROVED" }
            }
            // CI rollup: single state on the last commit.
            let rollup = (((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?
                .first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any]
            let ci = (rollup?["state"] as? String ?? "").uppercased()

            if review == "CHANGES_REQUESTED" { pr.status = "changes" }
            else if ci == "FAILURE" || ci == "ERROR" { pr.status = "fail" }
            else if ci == "PENDING" || ci == "EXPECTED" { pr.status = "pending" }
            else if review == "APPROVED" { pr.status = "approved" }
            else { pr.status = "neutral" }
        }

        // ---- unresolved review-thread counts (human vs bot) ----
        if let nodes = (node["reviewThreads"] as? [String: Any])?["nodes"] as? [[String: Any]] {
            var human = 0, bot = 0
            for t in nodes {
                if t["isResolved"] as? Bool == true { continue }
                let author = ((t["comments"] as? [String: Any])?["nodes"] as? [[String: Any]])?
                    .first?["author"] as? [String: Any]
                let l = author?["login"] as? String ?? ""
                let ty = author?["__typename"] as? String ?? ""
                if isBot(login: l, typename: ty) { bot += 1 } else { human += 1 }
            }
            pr.humanCount = human; pr.botCount = bot
        }
        return pr
    }

    /// Login names treated as bots even though GitHub types them as `User`.
    private static let botLogins: Set<String> = ["binks", "shopify-orc", "github-actions", "dependabot"]

    private static func isBot(login: String, typename: String) -> Bool {
        if typename == "Bot" { return true }
        let l = login.lowercased()
        if l.hasSuffix("[bot]") || l.hasSuffix("-bot") { return true }
        return botLogins.contains(l)
    }

    // ---- helpers ----
    // DateFormatter init is expensive; reuse one instance per format. Both are
    // only called from the single background fetch queue, so no concurrency issue.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static func daysAgo(_ n: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
        return dayFormatter.string(from: d)
    }
    static func timeStamp() -> String { timeFormatter.string(from: Date()) }
}
