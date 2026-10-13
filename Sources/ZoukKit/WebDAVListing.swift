import Foundation

// Reads a WebDAV PROPFIND (Depth: 1) reply into ScanEntry values, skipping folders.
enum WebDAVListing {
    static func entries(from data: Data) throws -> [ScanEntry] {
        let delegate = ListingParser()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { throw ScanClientError.invalidResponse }
        return delegate.entries
    }

    // WebDAV dates are HTTP dates ("Tue, 13 Oct 2026 00:38:33 GMT"); ScanEntry keeps ISO 8601.
    static func iso8601(fromHTTPDate value: String) -> String? {
        let httpDate = DateFormatter()
        httpDate.locale = Locale(identifier: "en_US_POSIX")
        httpDate.timeZone = TimeZone(identifier: "GMT")
        httpDate.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = httpDate.date(from: value) else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }
}

private final class ListingParser: NSObject, XMLParserDelegate {
    private(set) var entries: [ScanEntry] = []
    private var text = ""
    private var href: String?
    private var displayName: String?
    private var contentLength: Int?
    private var lastModified: String?
    private var isCollection = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "response":
            href = nil
            displayName = nil
            contentLength = nil
            lastModified = nil
            isCollection = false
        case "collection":
            isCollection = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "href":
            href = value
        case "displayname":
            displayName = value
        case "getcontentlength":
            contentLength = Int(value)
        case "getlastmodified":
            lastModified = value
        case "response":
            if let entry = currentEntry() { entries.append(entry) }
        default:
            break
        }
        text = ""
    }

    private func currentEntry() -> ScanEntry? {
        guard !isCollection, let href, !href.isEmpty else { return nil }
        let fallbackName = (href as NSString).lastPathComponent.removingPercentEncoding ?? href
        let name = (displayName?.isEmpty == false ? displayName : nil) ?? fallbackName
        let time = lastModified.flatMap(WebDAVListing.iso8601(fromHTTPDate:)) ?? ""
        return ScanEntry(name: name, size: contentLength ?? 0, time: time, path: href)
    }
}
