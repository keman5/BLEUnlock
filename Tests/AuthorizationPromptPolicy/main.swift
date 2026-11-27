import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

expect(AuthorizationPromptPolicy.requester(in: "允许管理员访问由“Python”启动的脚本吗？") == "Python",
       "Chinese script prompt identifies Python")
expect(AuthorizationPromptPolicy.requester(in: "Allow administrator access to scripts started by “Python”?") == "Python",
       "English script prompt identifies Python")
expect(AuthorizationPromptPolicy.allows(nil, allowedNames: []), "empty list allows all apps")
expect(AuthorizationPromptPolicy.allows("python", allowedNames: ["Python"]), "names match without case")
expect(!AuthorizationPromptPolicy.allows("Installer", allowedNames: ["Python"]), "other apps are rejected")
expect(!AuthorizationPromptPolicy.allows(nil, allowedNames: ["Python"]), "unknown requester is rejected in allowlist mode")
print("Authorization prompt policy checks passed")
