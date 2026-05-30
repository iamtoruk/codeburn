import Foundation

/// On-disk badge backstop. A static LaunchAgent runs `menubar-refresh.sh` every
/// 30s and atomically writes `menubar-status.json`; the app reads it as a badge
/// fallback when the in-app refresh loop is behind or dead. Shares the
/// `MenubarPayload` decoder with the live path — no separate data model.
struct MenubarStatusCache {
    let statusPath: String
    let scriptPath: String

    /// Default locations under `~/.cache/codeburn/`.
    static func standard() -> MenubarStatusCache {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/.cache/codeburn"
        return MenubarStatusCache(
            statusPath: "\(dir)/menubar-status.json",
            scriptPath: "\(dir)/menubar-refresh.sh"
        )
    }

    struct BadgeRead {
        let payload: MenubarPayload
        let ageSeconds: TimeInterval
    }

    /// Decodes the status file and returns it with its age (from the file's
    /// mtime). Returns nil when the file is missing, corrupt, unreadable, or
    /// older than `maxAgeSeconds` — every failure mode silently falls back to
    /// the in-memory payload, never crashes.
    func readBadgePayload(maxAgeSeconds: TimeInterval) -> BadgeRead? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: statusPath),
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        let age = Date().timeIntervalSince(mtime)
        guard age >= 0, age <= maxAgeSeconds else { return nil }
        guard let data = try? SafeFile.read(from: statusPath),
              let payload = try? JSONDecoder().decode(MenubarPayload.self, from: data) else {
            return nil
        }
        return BadgeRead(payload: payload, ageSeconds: age)
    }

    // Interpolated values are app-controlled: argv via CodeburnCLI.scriptEnvironment
    // (isSafe-validated) and period via the Period enum's fixed cliArg set.
    func writeRefreshScript(period: Period) throws {
        let env = CodeburnCLI.scriptEnvironment()
        let binCommand = env.argv.joined(separator: " ")
        let tmpPath = statusPath + ".tmp"
        let body = """
        #!/bin/sh
        export PATH="\(env.path)"
        TMP="\(tmpPath)"
        OUT="\(statusPath)"
        \(binCommand) status --format menubar-json --provider all --period \(period.cliArg) --no-optimize > "$TMP" 2>/dev/null && mv -f "$TMP" "$OUT" || rm -f "$TMP"
        """
        try SafeFile.write(Data(body.utf8), to: scriptPath, mode: 0o700)
    }
}
