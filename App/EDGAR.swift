import Foundation
import FoundationXML

struct Filing: Identifiable, Sendable {
    let id: String
    let title: String
    let form: String
    let url: URL
    let feedDate: Date?
    let firstSeen: Date
    let priority: Int
    let sentiment: String
    let reason: String
    var lagSeconds: Int? {
        guard let feedDate else { return nil }
        return Int(firstSeen.timeIntervalSince(feedDate).rounded())
    }
}

enum FilingJudge {
    static func rate(form: String, title: String) -> (Int, String, String) {
        let text = (form + " " + title).lowercased()
        // This is triage, not a confirmed trading signal.
        if ["424b5", "424b2", "s-3", "s-1", "offering", "bankruptcy", "delisting"].contains(where: text.contains) {
            return (85, "BEARISH?", "Potential offering / financing risk; read original.")
        }
        if ["merger", "tender offer", "acquisition", "material definitive agreement", "contract award"].contains(where: text.contains) {
            return (80, "BULLISH?", "Possible catalyst; terms require verification.")
        }
        if ["8-k", "6-k", "13d", "13g", "form 4"].contains(where: text.contains) || form == "4" {
            return (70, "REVIEW", "Event or ownership filing; inspect content.")
        }
        return (40, "REVIEW", "Unclassified. Read filing.")
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    private var inEntry = false
    private var currentTag = ""
    private var values: [String: String] = [:]
    private var items: [[String: String]] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String : String] = [:]) {
        let tag = elementName.lowercased()
        if tag == "entry" {
            inEntry = true
            values = [:]
        } else if inEntry {
            currentTag = tag
            if tag == "link", let href = attributeDict["href"], attributeDict["rel"] == "alternate" || values["link"] == nil {
                values["link"] = href
            }
            if tag == "category", let term = attributeDict["term"] {
                values["form"] = term
            }
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry, ["id", "title", "updated", "published"].contains(currentTag) else { return }
        values[currentTag, default: ""] += string
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName.lowercased() == "entry" {
            items.append(values)
            inEntry = false
        }
        currentTag = ""
    }
    static func parse(_ data: Data) throws -> [[String: String]] {
        let delegate = FeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? URLError(.cannotParseResponse) }
        return delegate.items
    }
}

actor EDGARService {
    private let url = URL(string: "https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&output=atom&count=100")!
    private var seen: [String: Filing] = [:]
    private let iso = ISO8601DateFormatter()

    func fetch() async throws -> [Filing] {
        var request = URLRequest(url: url)
        // Replace contact address below with a real monitored address if SEC requests identification.
        request.setValue("SEC-Filing-Sniper iPad app sec-sniper-contact@example.com", forHTTPHeaderField: "User-Agent")
        request.setValue("application/atom+xml, application/xml", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200 else {
            throw URLError(.badServerResponse)
        }
        let entries = try FeedParser.parse(data)
        guard !entries.isEmpty else { throw URLError(.cannotParseResponse) }
        let now = Date()
        for item in entries {
            guard let textURL = item["link"], let link = URL(string: textURL),
                  link.scheme == "https", link.host == "www.sec.gov",
                  let id = item["id"], !id.isEmpty else { continue }
            if seen[id] != nil { continue }
            let title = item["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled filing"
            let form = item["form"] ?? String(title.split(separator: " ").first ?? "")
            let timestamp = item["updated"] ?? item["published"]
            let date = timestamp.flatMap { ISO8601DateFormatter().date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let (priority, sentiment, reason) = FilingJudge.rate(form: form, title: title)
            seen[id] = Filing(id: id, title: title, form: form, url: link, feedDate: date,
                              firstSeen: now, priority: priority, sentiment: sentiment, reason: reason)
        }
        if seen.count > 500 {
            let keep = seen.values.sorted { $0.firstSeen > $1.firstSeen }.prefix(350)
            seen = Dictionary(uniqueKeysWithValues: keep.map { ($0.id, $0) })
        }
        return seen.values.sorted {
            if $0.firstSeen != $1.firstSeen { return $0.firstSeen > $1.firstSeen }
            return $0.title < $1.title
        }
    }
}
