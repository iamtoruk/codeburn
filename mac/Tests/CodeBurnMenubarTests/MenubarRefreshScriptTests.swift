import Foundation
import Testing
@testable import CodeBurnMenubar

@Suite("Menubar refresh script")
struct MenubarRefreshScriptTests {
    @Test("scriptEnvironment exposes a safe argv and augmented PATH")
    func scriptEnvironmentIsSafe() {
        let env = CodeburnCLI.scriptEnvironment()
        #expect(!env.argv.isEmpty)
        #expect(env.argv.allSatisfy { CodeburnCLI.isSafe($0) })
        // Homebrew + /usr/local are always appended for GUI-launched apps.
        #expect(env.path.contains("/opt/homebrew/bin"))
        #expect(env.path.contains("/usr/local/bin"))
    }

    private func tempDir() -> String {
        let dir = NSTemporaryDirectory() + "menubar-script-test-" + UUID().uuidString
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("generated script targets the status file and the requested period")
    func scriptContainsExpectedArgv() throws {
        let dir = tempDir()
        let statusPath = dir + "/menubar-status.json"
        let scriptPath = dir + "/menubar-refresh.sh"
        let cache = MenubarStatusCache(statusPath: statusPath, scriptPath: scriptPath)

        try cache.writeRefreshScript(period: .sevenDays)

        let body = try String(contentsOfFile: scriptPath, encoding: .utf8)
        #expect(body.contains("status --format menubar-json --provider all --period week --no-optimize"))
        #expect(body.contains(statusPath))
        #expect(body.contains("mv -f"))
        let perms = try FileManager.default.attributesOfItem(atPath: scriptPath)[.posixPermissions] as? NSNumber
        #expect(perms?.int16Value == 0o700)
    }
}
