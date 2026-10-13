// Self-check of KimiCore, run on the build machine before the app is built:
//   swiftc -o /tmp/coretest Kimi/KimiCore.swift Tests/main.swift && /tmp/coretest
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    if !ok { failures += 1; print("FAIL:", what) }
}

func messages(_ body: Data) -> [[String: String]] {
    let root = try! JSONSerialization.jsonObject(with: body) as! [String: Any]
    return root["messages"] as! [[String: String]]
}

// history: last 20, system first, never opening with the assistant
let long = (0..<30).map { ChatMessage(role: $0 % 2 == 0 ? .user : .assistant, text: "m\($0)") }
let sent = messages(try! KimiCore.requestBody(model: "m", history: long, voice: false))
check(sent.first?["role"] == "system", "system prompt first")
check(sent[1]["role"] == "user", "conversation opens with the user")
check(sent.count <= 21, "at most 20 history messages")
check(sent.last?["content"] == "m29", "latest message kept")
check(!(sent[0]["content"] ?? "").contains("вслух"), "no voice hint for typed questions")
check((messages(try! KimiCore.requestBody(model: "m", history: [], voice: true))[0]["content"] ?? "").contains("вслух"), "voice hint")

// replies
let ok = #"{"choices":[{"message":{"content":"  привет \n"}}]}"#.data(using: .utf8)!
check((try? KimiCore.parseReply(ok)) == "привет", "reply trimmed")
for bad in [#"{}"#, #"{"choices":[]}"#, #"{"choices":[{"message":{"content":"  "}}]}"#, "not json"] {
    check((try? KimiCore.parseReply(bad.data(using: .utf8)!)) == nil, "bad reply rejected: \(bad)")
}
check(KimiCore.errorText(#"{"error":{"message":"bad key"}}"#.data(using: .utf8)!) == "bad key", "API error message")
check(KimiCore.errorText("oops".data(using: .utf8)!) == "oops", "raw error text")

// the key is required and sent only as a header
check((try? KimiCore.request(key: "  ", model: "m", history: [], voice: false)) == nil, "empty key refused")
let req = try! KimiCore.request(key: " sk-1 ", model: "m", history: [], voice: false)
check(req.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1", "key trimmed into the header")
check(!(String(data: req.httpBody!, encoding: .utf8) ?? "").contains("sk-1"), "key never in the body")

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("KimiCore: all checks passed")
