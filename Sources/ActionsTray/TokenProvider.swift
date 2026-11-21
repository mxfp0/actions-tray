import Foundation
import Security

enum TokenSource: Sendable {
    case personal, ghCLI
}

struct ResolvedToken: Sendable {
    let token: String
    let source: TokenSource
}

enum TokenProvider {
    private static let service = "app.actionstray.ActionsTray"
    private static let account = "github-token"

    static func resolve() -> ResolvedToken? {
        if let token = savedToken() {
            return ResolvedToken(token: token, source: .personal)
        }
        if let token = ghCLIToken() {
            return ResolvedToken(token: token, source: .ghCLI)
        }
        return nil
    }

    static func save(_ token: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func savedToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty
        else { return nil }
        return token
    }

    // GUI apps don't inherit the shell PATH, so look for gh in the usual install locations.
    private static func ghCLIToken() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
