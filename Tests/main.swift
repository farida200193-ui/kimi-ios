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

// office: opening phrase, requests, parsing
check(KimiCore.opensOffice("Открой офис") && KimiCore.opensOffice("офис!") && !KimiCore.opensOffice("что нового в офисе?"), "open office phrase")
check((try? Office.ask("x", token: " ")) == nil, "office key required")
let askReq = try! Office.ask("Майкл, план", token: "t1")
check(askReq.url?.absoluteString == "https://ai.edu-upgrade.ru/office/ask" && askReq.value(forHTTPHeaderField: "Authorization") == "Bearer t1", "ask request")
let rej = try! JSONSerialization.jsonObject(with: try! Office.decide(5, approve: false, codeword: "secret", token: "t").httpBody!) as! [String: Any]
check(rej["decision"] as? String == "reject" && rej["codeword"] == nil && rej["confirmed"] as? Bool == true, "reject sends no code word")
let app = try! JSONSerialization.jsonObject(with: try! Office.decide(5, approve: true, codeword: "secret", token: "t").httpBody!) as! [String: Any]
check(app["codeword"] as? String == "secret" && app["id"] as? Int == 5, "approve carries the code word")
let root = try! Office.check(#"{"ok":true,"replies":[{"who":"Майкл · директор","text":"Сделаем"}],"proposals":[{"id":3,"text":"Джим: реклама"}]}"#.data(using: .utf8)!, 200)
check(Office.replies(root) == [Office.Reply(who: "Майкл · директор", text: "Сделаем")], "replies parsed")
check(Office.proposals(root) == [Office.Proposal(id: 3, text: "Джим: реклама")], "proposals parsed")
check((try? Office.check(#"{"ok":false,"error":"неверное кодовое слово"}"#.data(using: .utf8)!, 403)) == nil, "server error thrown")
do { _ = try Office.check(#"{"error":"неверное кодовое слово"}"#.data(using: .utf8)!, 403) } catch { check(error.localizedDescription == "неверное кодовое слово", "server error text") }

// personal voices
check(SpeechKit.voice(for: "Дуайт · охотник за партнёрами") == SpeechKit.Voice(name: "kirill", role: "strict", speed: 1.1), "agent voice by name")
check(SpeechKit.voice(for: "Офис") == SpeechKit.kimy, "unknown speaker speaks as Kimy")
check(SpeechKit.speakable("**Жирный** и `код`") == "Жирный и код", "markdown not read aloud")
let tts = try! SpeechKit.request("Привет", voice: SpeechKit.team["Райан"]!, key: " y1 ")
check(tts.value(forHTTPHeaderField: "Authorization") == "Api-Key y1", "SpeechKit key header")
let ttsBody = try! JSONSerialization.jsonObject(with: tts.httpBody!) as! [String: Any]
check((ttsBody["hints"] as! [[String: Any]]).count == 2, "no role sent for a voice without one")
check((try? SpeechKit.request("x", voice: SpeechKit.kimy, key: "")) == nil, "SpeechKit key required")
let mp3 = "{\"result\":{\"audioChunk\":{\"data\":\"\(Data([1, 2]).base64EncodedString())\"}}}\n{\"result\":{\"audioChunk\":{\"data\":\"\(Data([3]).base64EncodedString())\"}}}\n"
check(SpeechKit.audio(mp3.data(using: .utf8)!) == Data([1, 2, 3]), "audio chunks joined")

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("KimiCore: all checks passed")
