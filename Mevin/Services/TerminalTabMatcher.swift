import Foundation

/// Pure helpers for matching user-started Terminal tabs (PRD V6).
/// AppleScript matching lives in `TerminalStartupService`.
///
/// Matching rule: a tab matches a role tab when its foreground program runs in
/// the role tab's folder and its command line contains the configured command
/// (or the command's first word, e.g. `npm` for `npm run dev`). The foreground
/// program is read from `ps` per terminal device, skipping the shell itself, so
/// `npm run dev` is seen as `npm run dev` / `node …`, not as `-zsh`.
enum TerminalTabMatcher {
    /// Normalizes paths for comparison (`~`, symlinks when resolvable).
    static func normalizedPath(_ raw: String) -> String {
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return url.resolvingSymlinksInPath().path
    }

    static func normalizedCommand(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prefer false negatives: command must appear in process args or share basename.
    static func commandMatches(configured: String, processArgs: String) -> Bool {
        let cmd = normalizedCommand(configured)
        guard !cmd.isEmpty else { return processArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let args = processArgs.trimmingCharacters(in: .whitespacesAndNewlines)
        if args.isEmpty { return false }
        if args.localizedCaseInsensitiveContains(cmd) { return true }
        let base = (cmd as NSString).lastPathComponent
        if base.count >= 2, args.localizedCaseInsensitiveContains(base) { return true }
        return false
    }

    static func tabMatches(tab: TerminalTab, cwd: String, processArgs: String) -> Bool {
        let wantPath = normalizedPath(ProfileItem.effectiveTerminalPath(for: tab))
        let havePath = normalizedPath(cwd)
        guard wantPath == havePath else { return false }
        return commandMatches(configured: tab.trimmedCommand, processArgs: processArgs)
    }

    // MARK: - Foreground process (from `ps -A -o pid=,stat=,tty=,args=`)

    struct ProcessRow: Equatable {
        var pid: Int32
        var stat: String
        var tty: String
        var args: String
    }

    struct Foreground: Equatable {
        /// Process whose working folder stands for the tab.
        var pid: Int32
        /// Joined command lines of the non-shell foreground programs; empty
        /// when only the shell is in front (idle tab).
        var args: String
    }

    /// `/dev/ttys003`, `ttys003` and `s003` all become `s003`.
    static func normalizedTTY(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("/dev/") { value.removeFirst(5) }
        if value.hasPrefix("tty") { value.removeFirst(3) }
        return value
    }

    static func parseProcessList(_ text: String) -> [ProcessRow] {
        var rows: [ProcessRow] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]) else { continue }
            rows.append(
                ProcessRow(
                    pid: pid,
                    stat: String(parts[1]),
                    tty: normalizedTTY(String(parts[2])),
                    args: String(parts[3])
                )
            )
        }
        return rows
    }

    static func isShell(_ args: String) -> Bool {
        guard let first = args.split(separator: " ").first else { return true }
        var name = (String(first) as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() }
        return ["zsh", "bash", "sh", "fish", "tcsh", "csh", "ksh", "dash", "login"].contains(name)
    }

    /// The tab's foreground programs: processes on that terminal in the
    /// foreground group (`+` in stat). Shells are skipped unless nothing else runs.
    static func foreground(tty: String, in rows: [ProcessRow]) -> Foreground? {
        let key = normalizedTTY(tty)
        let front = rows.filter { $0.tty == key && $0.stat.contains("+") }
        guard !front.isEmpty else { return nil }
        let programs = front.filter { !isShell($0.args) }
        if let first = programs.first {
            return Foreground(pid: first.pid, args: programs.map(\.args).joined(separator: " "))
        }
        return Foreground(pid: front.last!.pid, args: "")
    }
}
