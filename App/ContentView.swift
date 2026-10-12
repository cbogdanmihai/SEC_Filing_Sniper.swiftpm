import SwiftUI

@MainActor
@Observable
final class FilingModel {
    var filings: [Filing] = []
    var lastCheck: Date?
    var lastSuccess: Date?
    var error: String?
    var refreshing = false
    private let client = EDGARService()
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        lastCheck = Date()
        defer { refreshing = false }
        do {
            filings = try await client.fetch()
            lastSuccess = Date()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private enum FilingSort: String, CaseIterable {
    case ticker = "Ticker", company = "Company", form = "Form", feed = "Feed Time"
    case detected = "Detected", lag = "Feed → Seen", score = "Score"
}

struct ContentView: View {
    @State private var model = FilingModel()
    @State private var search = ""
    @State private var priority = 0
    @State private var pollSeconds = 15
    @State private var sort: FilingSort = .feed
    @State private var ascending = false
    @Environment(\.scenePhase) private var scenePhase
    private static let et: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "MM/dd HH:mm:ss"
        return f
    }()
    private func time(_ d: Date?) -> String {
        d.map { Self.et.string(from: $0) } ?? "—"
    }
    private var rows: [Filing] {
        let subset = model.filings.filter {
            $0.priority >= priority && (search.isEmpty ||
                $0.company.localizedCaseInsensitiveContains(search) ||
                ($0.ticker ?? "").localizedCaseInsensitiveContains(search) ||
                $0.form.localizedCaseInsensitiveContains(search))
        }
        return subset.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case .ticker: comparison = (lhs.ticker ?? "ZZZZ").localizedStandardCompare(rhs.ticker ?? "ZZZZ")
            case .company: comparison = lhs.company.localizedStandardCompare(rhs.company)
            case .form: comparison = lhs.form.localizedStandardCompare(rhs.form)
            case .feed:
                comparison = (lhs.feedDate ?? .distantPast).compare(rhs.feedDate ?? .distantPast)
            case .detected: comparison = lhs.firstSeen.compare(rhs.firstSeen)
            case .lag:
                comparison = (lhs.lagSeconds ?? Int.min) < (rhs.lagSeconds ?? Int.min) ? .orderedAscending :
                    ((lhs.lagSeconds ?? Int.min) > (rhs.lagSeconds ?? Int.min) ? .orderedDescending : .orderedSame)
            case .score:
                comparison = lhs.priority < rhs.priority ? .orderedAscending :
                    (lhs.priority > rhs.priority ? .orderedDescending : .orderedSame)
            }
            if comparison == .orderedSame { return lhs.id < rhs.id }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    private func heading(_ kind: FilingSort, width: CGFloat, alignment: Alignment = .leading) -> some View {
        Button {
            if sort == kind { ascending.toggle() }
            else { sort = kind; ascending = kind == .ticker || kind == .company || kind == .form }
        } label: {
            HStack(spacing: 4) {
                Text(kind.rawValue)
                if sort == kind { Image(systemName: ascending ? "chevron.up" : "chevron.down") }
            }
            .font(.caption.bold())
            .foregroundStyle(sort == kind ? Color.orange : Color.white)
            .frame(width: width, alignment: alignment)
        }
        .buttonStyle(.plain)
    }
    private var header: some View {
        HStack(spacing: 12) {
            heading(.ticker, width: 95)
            heading(.company, width: 250)
            heading(.form, width: 85)
            heading(.feed, width: 130)
            heading(.detected, width: 130)
            heading(.lag, width: 100)
            heading(.score, width: 85, alignment: .trailing)
            Text("SEC ↗").font(.caption.bold()).frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 14)
        .background(Color(red: 0.14, green: 0.20, blue: 0.29))
    }
    private func line(_ f: Filing, index: Int) -> some View {
        HStack(spacing: 12) {
            Text(f.ticker ?? "—").foregroundStyle(f.ticker == nil ? Color.secondary : Color.cyan)
                .fontWeight(.bold).frame(width: 95, alignment: .leading)
            Text(f.company).lineLimit(1).frame(width: 250, alignment: .leading)
            Text(f.form).foregroundStyle(.yellow).frame(width: 85, alignment: .leading)
            Text(time(f.feedDate)).frame(width: 130, alignment: .leading)
            Text(time(f.firstSeen)).frame(width: 130, alignment: .leading)
            Text(f.lagSeconds.map { "\($0)s" } ?? "—")
                .foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text("\(f.priority) · \(f.sentiment)").foregroundStyle(f.sentiment.hasPrefix("BEAR") ? Color.red : (f.sentiment.hasPrefix("BULL") ? Color.green : Color.yellow))
                .lineLimit(1).minimumScaleFactor(0.75).frame(width: 85, alignment: .trailing)
            Link(destination: f.url) {
                Image(systemName: "arrow.up.right.square").foregroundStyle(.cyan)
                    .frame(width: 65, alignment: .trailing)
            }
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.horizontal, 12).padding(.vertical, 13)
        .background(index.isMultiple(of: 2) ? Color(red: 0.07, green: 0.12, blue: 0.19) : Color(red: 0.09, green: 0.15, blue: 0.23))
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("SEC SNIPER", systemImage: "bolt.fill").font(.title2.bold()).foregroundStyle(.orange)
                Spacer()
                Text(model.error == nil ? "● LIVE POLLING" : "● SOURCE ERROR")
                    .foregroundStyle(model.error == nil ? Color.green : Color.red).font(.caption.monospaced())
            }.padding()
            HStack(spacing: 12) {
                Picker("Priority", selection: $priority) {
                    Text("All").tag(0)
                    Text("High 70+").tag(70)
                    Text("Critical 85+").tag(85)
                }.pickerStyle(.segmented)
                TextField("Ticker / company / form", text: $search)
                    .textFieldStyle(.roundedBorder).frame(width: 240)
                Picker("Refresh", selection: $pollSeconds) {
                    Text("15 s").tag(15)
                    Text("30 s").tag(30)
                    Text("60 s").tag(60)
                }.frame(width: 110)
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.borderedProminent).disabled(model.refreshing)
            }.padding(.horizontal)
            HStack {
                Text("Checked: \(time(model.lastCheck)) ET")
                Spacer()
                Text("\(rows.count) shown / \(model.filings.count) total")
            }.font(.caption.monospaced()).foregroundStyle(.secondary).padding(12)
            if let error = model.error {
                Text("SEC ERROR: \(error)").foregroundStyle(.red).font(.caption)
            }
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    header
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, filing in
                                line(filing, index: index)
                            }
                        }
                    }
                }
                .frame(minWidth: 1060)
            }
            Text("Tap column headers to sort. Feed → Seen is NOT measured SEC publication latency. Tickers use SEC issuer CIK mapping; — means not verified. Polling only while app is active.")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }
        .background(Color(red: 0.035, green: 0.06, blue: 0.10))
        .preferredColorScheme(.dark)
        .task(id: pollSeconds) {
            await model.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(pollSeconds)) }
                catch { break }
                guard scenePhase == .active else { continue }
                await model.refresh()
            }
        }
    }
}
