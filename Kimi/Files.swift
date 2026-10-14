import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Files the owner attaches to a question, and Kimy's answer saved as a PDF report.
enum Files {
    static let types: [UTType] = [.pdf, .plainText, .commaSeparatedText, .tabSeparatedText, .json, .xml, .html, .text]

    struct Problem: LocalizedError { let errorDescription: String? }

    /// The text inside a picked file (from Files, iCloud, Telegram downloads…).
    static func read(_ url: URL) throws -> (name: String, text: String) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        let text: String
        if url.pathExtension.lowercased() == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw Problem(errorDescription: "Не открылся PDF «\(name)».") }
            text = doc.string ?? ""
        } else {
            let data = try Data(contentsOf: url)
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251) ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw Problem(errorDescription: "В «\(name)» нет текста (скан?). Пришлите текстовый PDF, CSV или TXT.")
        }
        return (name, text)
    }

    /// A paginated A4 PDF of the answer, ready to send.
    static func report(_ text: String) -> URL? {
        let body = NSMutableAttributedString(attributedString: NSAttributedString(markdown(text)))
        body.addAttribute(.font, value: UIFont.systemFont(ofSize: 12), range: NSRange(location: 0, length: body.length))
        let formatter = UISimpleTextPrintFormatter(attributedText: body)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 48, dy: 48), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, ["Title": "Отчёт Kimy"])
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH-mm"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Отчёт Kimy \(f.string(from: Date())).pdf")
        return (try? data.write(to: url, options: .atomic)) == nil ? nil : url
    }
}

/// iOS share sheet (Telegram, Почта, Файлы…), works on iOS 15.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
