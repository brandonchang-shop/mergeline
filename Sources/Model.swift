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

// MARK: - Cache (open instantly with last data)

private struct Cache: Codable {
    var open: [PR]
    var merged: [PR]
    var review: [PR]? = nil
    var mention: [PR]? = nil
    var updated: String
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
    @Published var ghState: GHState = .ok
    private var pendingRefresh = false
    @Published var updated = ""

    let settings = Settings()
    private let cachePath = "\(NSHomeDirectory())/.pi/mergeline_cache.json"
    private let enrichCount = 6
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
    }
    private func saveCache() {
        let c = Cache(open: openPRs, merged: mergedPRs, review: reviewPRs, mention: mentionPRs, updated: updated)
        if let data = try? JSONEncoder().encode(c) {
            try? data.write(to: URL(fileURLWithPath: cachePath))
        }
    }

    // ---- Refresh PRs (background) ----
    func refresh() {
        // If a refresh is already running, don't drop this request — remember it
        // and re-run once the current one finishes (picks up the latest settings,
        // e.g. a changed recent-days window).
        if loading { pendingRefresh = true; return }
        loading = true
        let days = settings.recentDays
        let since = Self.daysAgo(days)
        let includeTeam = settings.includeTeamReviews
        let q = DispatchQueue.global(qos: .userInitiated)

        // Do everything off the main thread, starting with the gh dependency
        // check. If gh is missing/not-authed, surface a clear message and skip
        // the fetches (which would otherwise just return empty lists).
        q.async { [weak self] in
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

            // Run the three gh queries concurrently and publish each section as
            // soon as it returns (no section waits behind another).
            let group = DispatchGroup()
            group.enter()
            q.async {
                defer { group.leave() }
                let open = self.fetchPRs(who: ["--author", "@me"], extraArgs: ["--state", "open"], enrich: true)
                DispatchQueue.main.async { self.openPRs = open }
            }
            group.enter()
            q.async {
                defer { group.leave() }
                let merged = self.fetchPRs(who: ["--author", "@me"], extraArgs: ["--merged", "--merged-at", ">=\(since)"], enrich: false)
                DispatchQueue.main.async { self.mergedPRs = merged }
            }
            group.enter()
            q.async {
                defer { group.leave() }
                // Direct-only uses the `user-review-requested:@me` qualifier (excludes
                // team requests); team-inclusive uses gh's --review-requested flag.
                let reviewWho = includeTeam
                    ? ["--review-requested", "@me"]
                    : ["user-review-requested:@me"]
                let review = self.fetchPRs(who: reviewWho, extraArgs: ["--state", "open"], enrich: true)
                DispatchQueue.main.async { self.reviewPRs = review }
            }
            group.enter()
            q.async {
                defer { group.leave() }
                // Open PRs where I'm @mentioned (body or comments), incl. PRs I don't own.
                let mentions = self.fetchPRs(who: ["--mentions", "@me"], extraArgs: ["--state", "open"], enrich: true)
                DispatchQueue.main.async { self.mentionPRs = mentions }
            }

            group.notify(queue: .main) { [weak self] in
                guard let self else { return }
                // Drop mention PRs I authored (already in Open PRs) to avoid duplicates.
                let openURLs = Set(self.openPRs.map(\.url))
                self.mentionPRs.removeAll { openURLs.contains($0.url) }
                self.updated = Self.timeStamp()
                self.loading = false
                self.saveCache()
                if self.pendingRefresh { self.pendingRefresh = false; self.refresh() }
            }
        }
    }

    /// Detect whether `gh` is installed and authenticated.
    private static func checkGH() -> GHState {
        if Shell.run(["gh", "--version"]).isEmpty { return .missing }
        // `gh auth token` prints a token to stdout only when authenticated.
        return Shell.run(["gh", "auth", "token"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? .notAuthed : .ok
    }

    private func fetchPRs(who: [String], extraArgs: [String], enrich: Bool) -> [PR] {
        var args = ["gh", "search", "prs"] + who +
                   ["--sort", "updated", "--order", "desc", "--limit", "30",
                    "--json", "title,url,repository"]
        args.append(contentsOf: extraArgs)
        let out = Shell.run(args)
        guard let data = out.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var prs: [PR] = []
        for item in arr {
            let title = item["title"] as? String ?? ""
            let url = item["url"] as? String ?? ""
            let repo = (item["repository"] as? [String: Any])?["name"] as? String ?? ""
            guard !url.isEmpty else { continue }
            var pr = PR(repo: repo, title: title, url: url)
            if !enrich { pr.status = "merged" }
            prs.append(pr)
        }

        // Enrich the top N PRs' status in parallel (each is a separate `gh pr view`
        // network call; running them serially was the main source of latency).
        if enrich {
            let n = min(enrichCount, prs.count)
            let lock = NSLock()
            DispatchQueue.concurrentPerform(iterations: n) { i in
                let s = self.status(for: prs[i].url)
                let (human, bot) = self.unresolvedThreadCounts(for: prs[i].url)
                lock.lock()
                prs[i].status = s
                prs[i].humanCount = human
                prs[i].botCount = bot
                lock.unlock()
            }
        }
        return prs
    }

    /// Returns a status key for a PR based on review decision + CI rollup.
    private func status(for url: String) -> String {
        let out = Shell.run(["gh", "pr", "view", url,
                             "--json", "reviewDecision,isDraft,statusCheckRollup"])
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "neutral" }

        if obj["isDraft"] as? Bool == true { return "draft" }
        let review = obj["reviewDecision"] as? String ?? ""
        var ci = "none"
        if let checks = obj["statusCheckRollup"] as? [[String: Any]] {
            var fail = false, pending = false, any = false
            for c in checks {
                any = true
                if (c["__typename"] as? String) == "CheckRun" {
                    let concl = (c["conclusion"] as? String ?? "").uppercased()
                    let st = (c["status"] as? String ?? "").uppercased()
                    if ["FAILURE","CANCELLED","TIMED_OUT","ACTION_REQUIRED","STARTUP_FAILURE"].contains(concl) { fail = true }
                    else if st != "COMPLETED" { pending = true }
                } else {
                    let s = (c["state"] as? String ?? "").uppercased()
                    if s == "FAILURE" || s == "ERROR" { fail = true }
                    else if s == "PENDING" { pending = true }
                }
            }
            ci = fail ? "fail" : (pending ? "pending" : (any ? "pass" : "none"))
        }
        if review == "CHANGES_REQUESTED" { return "changes" }
        if ci == "fail" { return "fail" }
        if ci == "pending" { return "pending" }
        if review == "APPROVED" { return "approved" }
        return "neutral"
    }

    /// Login names treated as bots even though GitHub types them as `User`.
    private static let botLogins: Set<String> = ["binks", "shopify-orc", "github-actions", "dependabot"]

    private static func isBot(login: String, typename: String) -> Bool {
        if typename == "Bot" { return true }
        let l = login.lowercased()
        if l.hasSuffix("[bot]") || l.hasSuffix("-bot") { return true }
        return botLogins.contains(l)
    }

    /// Counts UNRESOLVED review threads on a PR, split into human vs bot by the
    /// thread's first comment author. Returns (human, bot). Uses one GraphQL call.
    private func unresolvedThreadCounts(for url: String) -> (Int, Int) {
        // Parse https://github.com/OWNER/REPO/pull/NUMBER
        guard let comps = URLComponents(string: url) else { return (0, 0) }
        let parts = comps.path.split(separator: "/").map(String.init)  // [OWNER, REPO, "pull", NUMBER]
        guard parts.count >= 4, parts[2] == "pull", let number = Int(parts[3]) else { return (0, 0) }
        let owner = parts[0], repo = parts[1]

        let query = """
        query($owner:String!,$repo:String!,$number:Int!){
          repository(owner:$owner,name:$repo){
            pullRequest(number:$number){
              reviewThreads(first:100){ nodes {
                isResolved
                comments(first:1){ nodes { author { login __typename } } }
              }}
            }
          }
        }
        """
        let out = Shell.run(["gh", "api", "graphql",
                             "-f", "query=\(query)",
                             "-F", "owner=\(owner)", "-F", "repo=\(repo)", "-F", "number=\(number)"])
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              let repoObj = dataObj["repository"] as? [String: Any],
              let pr = repoObj["pullRequest"] as? [String: Any],
              let threads = pr["reviewThreads"] as? [String: Any],
              let nodes = threads["nodes"] as? [[String: Any]]
        else { return (0, 0) }

        var human = 0, bot = 0
        for t in nodes {
            if t["isResolved"] as? Bool == true { continue }   // only OPEN threads
            let author = ((t["comments"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["author"] as? [String: Any]
            let login = author?["login"] as? String ?? ""
            let typename = author?["__typename"] as? String ?? ""
            if Self.isBot(login: login, typename: typename) { bot += 1 } else { human += 1 }
        }
        return (human, bot)
    }

    // ---- helpers ----
    static func daysAgo(_ n: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    static func timeStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: Date())
    }
}
