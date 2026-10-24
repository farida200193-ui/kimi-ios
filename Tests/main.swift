// Self-check of KimiCore, run on the build machine before the app is built:
//   swiftc -o /tmp/coretest Kimi/KimiCore.swift Kimi/Agent.swift Kimi/Council.swift Tests/main.swift && /tmp/coretest
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

// attached files go to the model, not on screen
let att = KimiCore.attachment([(name: "sales.csv", text: "день,сумма\n1,100")])!
check(att.contains("Файл «sales.csv»") && att.contains("1,100"), "file text in the attachment")
check(KimiCore.attachment([]) == nil, "no files, no attachment")
check(KimiCore.attachment([(name: "big.txt", text: String(repeating: "я", count: 70_000))])!.contains("обрезано"), "big file cut")
let withFile = messages(try! KimiCore.requestBody(model: "m", history: [ChatMessage(role: .user, text: "Сделай отчёт", files: ["sales.csv"], attachment: att)], voice: false))
check(withFile[1]["content"]!.hasPrefix("Файл «sales.csv»") && withFile[1]["content"]!.hasSuffix("Сделай отчёт"), "attachment sent before the question")

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

// agent: prompt lists only what the owner allowed
let utc = TimeZone(identifier: "Europe/Moscow")!
let ctx0 = Agent.context(access: [:], mcp: [:], mcpAccess: [:], memory: [], now: Date(timeIntervalSince1970: 0), zone: utc)
check(ctx0.contains("Подключённых приложений нет") && !ctx0.contains("calendar.list"), "no connectors, no tools")
let ctx1 = Agent.context(access: ["calendar": .read, "messages": .act], mcp: ["notion": [Agent.RemoteTool(name: "search", about: "Поиск", args: ["query"], readOnly: true), Agent.RemoteTool(name: "create", about: "Создать", args: [], readOnly: false)]],
                         mcpAccess: ["notion": .read], memory: ["Жена — Алия"], now: Date(timeIntervalSince1970: 0), zone: utc)
check(ctx1.contains("calendar.list") && !ctx1.contains("calendar.add"), "read access hides acting tools")
check(ctx1.contains("message.send") && ctx1.contains("1. Жена — Алия"), "act tools and memory in prompt")
check(ctx1.contains("\"tool\":\"search\"") && !ctx1.contains("\"tool\":\"create\""), "MCP read-only tools only")
check(ctx1.contains("1970-01-01 03:00"), "current time in the owner's zone")
let body = messages(try! KimiCore.requestBody(model: "m", history: [ChatMessage(role: .user, text: "q")], voice: false, context: ctx1))
check(body[0]["content"]!.contains("calendar.list"), "context goes into the system prompt")

// agent: reply parsing
let reply = "Смотрю календарь.\n[[ACTION {\"tool\":\"calendar.list\",\"args\":{\"from\":\"2026-10-15\",\"days\":2}}]]\n[[ЗАПОМНИ: Любит кофе без сахара]] [[ЗАБУДЬ: 2]]"
let parsed = Agent.parse(reply)
check(parsed.text == "Смотрю календарь.", "marks removed from the visible text: \(parsed.text)")
check(parsed.actions == [Agent.Action(tool: "calendar.list", args: ["from": "2026-10-15", "days": "2"])], "action parsed")
check(parsed.remember == ["Любит кофе без сахара"] && parsed.forget == [2], "memory marks")
let mcpReply = Agent.parse("[[ACTION {\"tool\":\"mcp\",\"args\":{\"server\":\"notion\",\"tool\":\"search\",\"args\":{\"query\":\"план\"}}}]]")
check(mcpReply.actions.first?.args["args"] == "{\"query\":\"план\"}" && mcpReply.text.isEmpty, "nested MCP args kept as JSON")
check(Agent.parse("[[ACTION {broken]]").actions.isEmpty, "broken action ignored")

// agent: who decides
let acc: [String: Agent.Access] = ["calendar": .read, "reminders": .act]
check(Agent.gate(Agent.Action(tool: "calendar.list", args: [:]), access: acc, mcp: [:], mcpAccess: [:]) == .run, "reading runs by itself")
check(Agent.gate(Agent.Action(tool: "office.proposals", args: [:]), access: ["office": .read], mcp: [:], mcpAccess: [:]) == .run, "Kimy sees what waits in the Office")
if case .refuse = Agent.gate(Agent.Action(tool: "calendar.add", args: [:]), access: acc, mcp: [:], mcpAccess: [:]) {} else { check(false, "read-only refuses acting") }
check(Agent.gate(Agent.Action(tool: "reminders.add", args: [:]), access: acc, mcp: [:], mcpAccess: [:]) == .ask, "acting always asks")
if case .refuse = Agent.gate(Agent.Action(tool: "contacts.find", args: [:]), access: acc, mcp: [:], mcpAccess: [:]) {} else { check(false, "off connector refused") }
if case .refuse = Agent.gate(Agent.Action(tool: "rm.rf", args: [:]), access: acc, mcp: [:], mcpAccess: [:]) {} else { check(false, "unknown tool refused") }
let tools = ["notion": [Agent.RemoteTool(name: "search", about: "", args: [], readOnly: true), Agent.RemoteTool(name: "create", about: "", args: [], readOnly: false)]]
check(Agent.gate(Agent.Action(tool: "mcp", args: ["server": "notion", "tool": "search"]), access: [:], mcp: tools, mcpAccess: ["notion": .read]) == .run, "MCP read")
check(Agent.gate(Agent.Action(tool: "mcp", args: ["server": "notion", "tool": "create"]), access: [:], mcp: tools, mcpAccess: ["notion": .act]) == .ask, "MCP write asks")
if case .refuse = Agent.gate(Agent.Action(tool: "mcp", args: ["server": "notion", "tool": "create"]), access: [:], mcp: tools, mcpAccess: ["notion": .read]) {} else { check(false, "MCP write refused on read") }

// agent: links into the owner's apps
check(Agent.messageURL(["app": "whatsapp", "to": "+7 (900) 111-22-33", "text": "Привет & пока"])?.absoluteString == "https://wa.me/79001112233?text=%D0%9F%D1%80%D0%B8%D0%B2%D0%B5%D1%82%20%26%20%D0%BF%D0%BE%D0%BA%D0%B0", "WhatsApp link")
check(Agent.messageURL(["app": "telegram", "to": "@alina", "text": "hi"])?.absoluteString == "tg://resolve?domain=alina&text=hi", "Telegram by username")
check(Agent.messageURL(["app": "sms", "to": "+7 900", "text": "a=b"])?.absoluteString == "sms:+7900&body=a%3Db", "SMS link")
check(Agent.messageURL(["app": "mail", "to": "a@b.ru", "subject": "Тест", "text": "x"])?.absoluteString.hasPrefix("mailto:a@b.ru?subject=") == true, "mail link")
check(Agent.messageURL(["app": "fax", "text": "x"]) == nil, "unknown messenger")
check(Agent.shortcutURL("Свет в гостиной", input: nil)?.absoluteString == "shortcuts://run-shortcut?name=%D0%A1%D0%B2%D0%B5%D1%82%20%D0%B2%20%D0%B3%D0%BE%D1%81%D1%82%D0%B8%D0%BD%D0%BE%D0%B9", "shortcut link")
check(Agent.shortcutURL(" ", input: nil) == nil, "empty shortcut name")
check(Agent.date("2026-10-15 09:30", zone: utc) == Date(timeIntervalSince1970: 1_792_045_800), "date parsed in the owner's zone")
check(Agent.date("завтра") == nil, "free text is not a date")

// agent: MCP
check((try? Agent.MCP.request(url: URL(string: "http://x.ru/mcp")!, token: "", session: nil, id: 1, method: "tools/list")) == nil, "MCP needs https")
let mreq = try! Agent.MCP.request(url: URL(string: "https://mcp.notion.com/mcp")!, token: " t ", session: "s1", id: 2, method: "tools/list")
check(mreq.value(forHTTPHeaderField: "Authorization") == "Bearer t" && mreq.value(forHTTPHeaderField: "Mcp-Session-Id") == "s1", "MCP headers")
let sse = "event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"tools\":[{\"name\":\"search\",\"description\":\"Find\",\"inputSchema\":{\"properties\":{\"query\":{},\"limit\":{}}},\"annotations\":{\"readOnlyHint\":true}},{\"name\":\"create\"}]}}\n\n"
let listed = Agent.MCP.tools(try! Agent.MCP.result(Data(sse.utf8)))
check(listed == [Agent.RemoteTool(name: "search", about: "Find", args: ["limit", "query"], readOnly: true), Agent.RemoteTool(name: "create", about: "", args: [], readOnly: false)], "MCP tools from an event stream")
check(Agent.MCP.text(try! Agent.MCP.result(Data(#"{"result":{"content":[{"type":"text","text":"ok"}]}}"#.utf8))) == "ok", "MCP plain JSON result")
check((try? Agent.MCP.result(Data(#"{"error":{"message":"нет доступа"}}"#.utf8))) == nil, "MCP error thrown")

// idea council
check(Council.questions("Вот вопросы:\n```json\n{\"questions\":[\"Бюджет?\",\" Сроки? \",\"Что пробовали?\",\"лишний\"]}\n```") == ["Бюджет?", "Сроки?", "Что пробовали?"], "chairman questions from fenced JSON")
check(Council.questions("не json").isEmpty, "no questions from text")
let council = Council.result(#"{"debate":[{"who":"Стратег","say":"Рынок мал"}],"scores":[{"who":"Стратег","score":7},{"who":"Финансист","score":"3"},{"who":"Офферщик","score":12.4}],"ruin":"7,5","conditions":["a","b","c","d","e"]}"#)!
check(council.scores.map(\.score) == [7, 3, 10], "scores parsed and clamped")
check(council.ruin == 7.5 && council.conditions.count == 4 && council.debate.count == 1, "ruin, conditions, debate")
check(Council.format(council.average) == "6,7" && Council.verdict(council.average) == "ДЕЛАТЬ С УСЛОВИЯМИ", "average and verdict")
check(Council.verdict(3) == "НЕ ДЕЛАТЬ" && Council.verdict(8) == "ДЕЛАТЬ", "verdict bounds")
check(Council.result(#"{"debate":[]}"#) == nil, "no scores, no result")
check(Council.councilPrompt("кофейня", answers: [(q: "Бюджет?", a: "")]).contains("(не ответил)"), "unanswered question marked")
check(Council.report(idea: "кофейня", answers: [], result: council).contains("Вердикт 6,7/10"), "report text")

// personal trainer
check(Agent.weekdays("Пн, ср,ПЯТНИЦА") == [2, 4, 6] && Agent.weekdays("каждый день").isEmpty && Agent.weekdays("сб вс сб") == [1, 7], "weekdays")
check(Agent.gate(Agent.Action(tool: "health.steps", args: [:]), access: ["health": .read], mcp: [:], mcpAccess: [:]) == .run, "steps read by itself")
check(Agent.gate(Agent.Action(tool: "steps.goal", args: ["steps": "8000"]), access: ["health": .act], mcp: [:], mcpAccess: [:]) == .ask, "step goal asks first")
check(Agent.gate(Agent.Action(tool: "calendar.series", args: [:]), access: ["calendar": .act], mcp: [:], mcpAccess: [:]) == .ask, "training series asks first")
check(Agent.describe(Agent.Action(tool: "calendar.series", args: ["title": "Силовая", "start": "2026-10-16 08:00", "days": "пн,ср,пт", "weeks": "4"])).contains("пн,ср,пт"), "series described")
check(ctx0.contains("уровень подготовки"), "trainer skill always in the prompt")

// voice conversation
check(KimiCore.endsConversation("Стоп!") && KimiCore.endsConversation(" хватит ") && !KimiCore.endsConversation("стоп-кран это что"), "stop words")
check(KimiCore.yesNo("Да.") == true && KimiCore.yesNo("Не надо") == false && KimiCore.yesNo("да, но в пятницу") == nil, "spoken approval")

// Kimy account: brain and office on the server
let signupReq = try! Account.signup(name: "Анна", company: "Пекарня", invite: "")
check(signupReq.url?.absoluteString == "https://ai.edu-upgrade.ru/kimy/signup" && signupReq.value(forHTTPHeaderField: "Authorization") == nil, "signup needs no key")
let brainReq = try! KimiCore.request(key: "kt_1", model: "m", history: [], voice: false, endpoint: Account.chat)
check(brainReq.url?.absoluteString == "https://ai.edu-upgrade.ru/kimy/chat" && brainReq.value(forHTTPHeaderField: "Authorization") == "Bearer kt_1", "brain on the server")
Office.tenant = true
check((try! Office.ask("x", token: "kt_1")).url?.absoluteString == "https://ai.edu-upgrade.ru/kimy/office/ask", "own office through the account")
Office.tenant = false
check((try! Office.ask("x", token: "t")).url?.absoluteString == "https://ai.edu-upgrade.ru/office/ask", "owner office unchanged")
let st = Account.status(["company": "Пекарня", "office": "работает", "steps": ["business": true, "telegram_bot": true, "telegram_group": false],
                         "telegram": ["bot": "pekarnya_bot", "code": "KIMY-123456"], "chat_today": 3, "chat_limit": 200])
check(st.running && st.business && st.telegramBot && !st.telegramGroup && st.code == "KIMY-123456" && st.chatLimit == 200, "account status")
check(SpeechKit.voice(for: "Артём · директор").name == "alexander", "voices of the users' team")

if failures > 0 { print("\(failures) check(s) failed"); exit(1) }
print("KimiCore: all checks passed")
