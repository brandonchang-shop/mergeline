import AppKit
import SwiftUI

// MARK: - Data types

struct PR: Identifiable {
    let id: String        // url
    let repo: String
    let title: String
    let url: String
    var symbol: String = "arrow.triangle.branch"
    var color: Color = .secondary
}

struct Todo: Identifiable {
    let id = UUID()
    var text: String
    var done: Bool
}

// MARK: - Shell helper

enum Shell {
    /// Extra dirs prepended to PATH so `gh`/`jq` resolve under SwiftBar-like minimal env.
    static let extraPath = [
        "\(NSHomeDirectory())/.local/state/tec/toolchain/base_profile/bin",
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"
    ].joined(separator: ":")

    @discardableResult
    static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
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

// MARK: - Store

final class DashStore: ObservableObject {
    @Published var openPRs: [PR] = []
    @Published var mergedPRs: [PR] = []
    @Published var todos: [Todo] = []
    @Published var loading = false
    @Published var updated = ""
    @Published var standupText: String? = nil
    @Published var standupLoading = false

    private let todoPath = "\(NSHomeDirectory())/.pi/todo.md"
    private let enrichCount = 6   // how many open PRs get a live status dot

    init() { loadTodos() }

    // ---- Refresh PRs (background) ----
    func refresh() {
        loadTodos()
        if loading { return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let open = self.fetchPRs(extraArgs: ["--state", "open"], enrich: true)
            let since = Self.daysAgo(7)
            let merged = self.fetchPRs(extraArgs: ["--merged", "--merged-at", ">=\(since)"], enrich: false)
            let stamp = Self.timeStamp()
            DispatchQueue.main.async {
                self.openPRs = open
                self.mergedPRs = merged
                self.updated = stamp
                self.loading = false
            }
        }
    }

    private func fetchPRs(extraArgs: [String], enrich: Bool) -> [PR] {
        var args = ["gh", "search", "prs", "--author", "@me",
                    "--sort", "updated", "--order", "desc", "--limit", "30",
                    "--json", "title,url,repository"]
        args.append(contentsOf: extraArgs)
        let out = Shell.run(args)
        guard let data = out.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var prs: [PR] = []
        for (i, item) in arr.enumerated() {
            let title = item["title"] as? String ?? ""
            let url = item["url"] as? String ?? ""
            let repo = (item["repository"] as? [String: Any])?["name"] as? String ?? ""
            guard !url.isEmpty else { continue }
            var pr = PR(id: url, repo: repo, title: title, url: url)
            if enrich && i < enrichCount {
                (pr.symbol, pr.color) = self.status(for: url)
            } else if !enrich {
                pr.symbol = "arrow.triangle.merge"; pr.color = .green
            }
            prs.append(pr)
        }
        return prs
    }

    /// Returns (SFSymbol, color) for a PR based on review decision + CI rollup.
    private func status(for url: String) -> (String, Color) {
        let out = Shell.run(["gh", "pr", "view", url,
                             "--json", "reviewDecision,isDraft,statusCheckRollup"])
        guard let data = out.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("arrow.triangle.branch", .secondary) }

        if obj["isDraft"] as? Bool == true { return ("pencil.circle", .secondary) }
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

        if review == "CHANGES_REQUESTED" { return ("xmark.octagon.fill", .red) }
        if ci == "fail" { return ("exclamationmark.triangle.fill", .orange) }
        if ci == "pending" { return ("clock.fill", .yellow) }
        if review == "APPROVED" { return ("checkmark.seal.fill", .green) }
        return ("arrow.triangle.branch", .secondary)
    }

    // ---- AI standup ----
    func generateStandup() {
        standupLoading = true
        standupText = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let since = Self.daysAgo(7)
            let jq = ".[] | \"- \\(.repository.name): \\(.title)\""
            let merged = Shell.run(["gh", "search", "prs", "--author", "@me", "--merged",
                "--merged-at", ">=\(since)", "--limit", "30", "--json", "title,repository", "--jq", jq])
            let open = Shell.run(["gh", "search", "prs", "--author", "@me", "--state", "open",
                "--limit", "30", "--json", "title,repository", "--jq", jq])
            let prompt = """
            Write a short first-person standup update as a natural spoken script I can read aloud to my team — \
            flowing sentences in one or two short paragraphs, NOT bullet points, NOT labeled sections, no headers. \
            Cover what I shipped recently, what I'm working on now, and any blockers, woven together conversationally. \
            Keep it under ~120 words, group related PRs, and don't invent anything beyond the data below.

            RECENTLY MERGED (last 7 days):
            \(merged.isEmpty ? "(none)" : merged)

            CURRENTLY OPEN PRS:
            \(open.isEmpty ? "(none)" : open)
            """
            let result = Shell.run(["claude", "-p", prompt]).trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                self.standupText = result.isEmpty ? "Standup generation failed. Check `claude` CLI." : result
                self.standupLoading = false
            }
        }
    }

    // ---- Todos (read/write ~/.pi/todo.md) ----
    func loadTodos() {
        var result: [Todo] = []
        if let content = try? String(contentsOfFile: todoPath, encoding: .utf8) {
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(line)
                if let r = s.range(of: #"^\s*-\s*\[ \]\s*"#, options: .regularExpression) {
                    result.append(Todo(text: String(s[r.upperBound...]), done: false))
                } else if let r = s.range(of: #"^\s*-\s*\[[xX]\]\s*"#, options: .regularExpression) {
                    result.append(Todo(text: String(s[r.upperBound...]), done: true))
                }
            }
        }
        todos = result
    }

    private func saveTodos() {
        var lines = ["# Todo"]
        for t in todos { lines.append("- [\(t.done ? "x" : " ")] \(t.text)") }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: todoPath, atomically: true, encoding: .utf8)
    }

    func addTodo(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        todos.append(Todo(text: t, done: false)); saveTodos()
    }
    func toggle(_ todo: Todo) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].done.toggle(); saveTodos()
    }
    func edit(_ todo: Todo, to newText: String) {
        guard let i = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[i].text = newText.trimmingCharacters(in: .whitespaces); saveTodos()
    }
    func delete(_ todo: Todo) {
        todos.removeAll { $0.id == todo.id }; saveTodos()
    }
    func clearCompleted() { todos.removeAll { $0.done }; saveTodos() }

    // ---- helpers ----
    static func daysAgo(_ n: Int) -> String {
        let d = Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
    static func timeStamp() -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: Date())
    }
}
