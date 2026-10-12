import SwiftUI

@MainActor
@Observable
final class FilingModel {
    var filings: [Filing] = []
    var lastCheck: Date?
    var lastSuccess: Date?
    var error: String?
    var refreshInProgress = false
    private let client = EDGARService()

    func refresh() async {
        guard !refreshInProgress else { return }
        refreshInProgress = true
        lastCheck = Date()
        defer { refreshInProgress = false }
        do {
            filings = try await client.fetch()
            lastSuccess = Date()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ContentView: View {
    @State private var model = FilingModel()
    @State private var search = ""
    @State private var priority = 0
    @State private var pollSeconds = 15
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [Filing] {
        model.filings.filter {
            $0.priority >= priority && (search.isEmpty ||
                $0.title.localizedCaseInsensitiveContains(search) ||
                $0.form.localizedCaseInsensitiveContains(search))
        }
    }
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "MM/dd HH:mm:ss"
        return f
    }()
    private func time(_ value: Date?) -> String {
        guard let value else { return "N/A" }
        return Self.clock.string(from: value) + " ET"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Label("SEC SNIPER", systemImage: "bolt.fill")
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                    Spacer()
                    Image(systemName: model.error == nil && model.lastSuccess != nil ? "circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(model.error == nil && model.lastSuccess != nil ? .green : .orange)
                    Text(model.error == nil ? (model.lastSuccess == nil ? "CONNECTING" : "LIVE POLLING") : "SOURCE ERROR")
                        .font(.caption.monospaced())
                }
                .padding([.horizontal, .top])

                HStack(spacing: 12) {
                    Picker("Priority", selection: $priority) {
                        Text("All").tag(0)
                        Text("High 70+").tag(70)
                        Text("Critical 85+").tag(85)
                    }
                    .pickerStyle(.segmented)
                    Picker("Refresh", selection: $pollSeconds) {
                        Text("15 s").tag(15)
                        Text("30 s").tag(30)
                        Text("60 s").tag(60)
                    }
                    .frame(maxWidth: 120)
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.refreshInProgress)
                    .buttonStyle(.borderedProminent)
                }
                .padding()

                HStack {
                    Text("Checked: \(time(model.lastCheck))")
                    Spacer()
                    Text("\(model.filings.count) filings")
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                if let error = model.error {
                    Text("SEC error: \(error)")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                if filtered.isEmpty {
                    ContentUnavailableView("No filings loaded", systemImage: "antenna.radiowaves.left.and.right",
                                           description: Text("SEC may be unavailable or no filings match."))
                } else {
                    List(filtered) { filing in
                        Link(destination: filing.url) {
                            FilingRow(filing: filing, feedTime: time(filing.feedDate), seenTime: time(filing.firstSeen))
                        }
                        .listRowBackground(Color(red: 0.09, green: 0.15, blue: 0.23))
                    }
                    .listStyle(.plain)
                    .searchable(text: $search, prompt: "Company or form")
                }
                Text("Feed time ≠ independently verified public or acceptance time. Lag = detection minus feed time. Indicative classification only. Polling stops when iPadOS suspends the app.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .background(Color(red: 0.035, green: 0.06, blue: 0.10))
            .task(id: pollSeconds) {
                await model.refresh()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(pollSeconds)) }
                    catch { break }
                    guard scenePhase == .active else { continue }
                    await model.refresh()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

struct FilingRow: View {
    let filing: Filing
    let feedTime: String
    let seenTime: String

    var color: Color {
        if filing.sentiment.hasPrefix("BULL") { return .green }
        if filing.sentiment.hasPrefix("BEAR") { return .red }
        return .yellow
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(filing.form.isEmpty ? "SEC" : filing.form)
                    .font(.caption.bold())
                    .padding(6)
                    .background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 5))
                Text(filing.sentiment).font(.caption.bold()).foregroundStyle(color)
                Spacer()
                Text("\(filing.priority)/100").font(.headline.monospacedDigit()).foregroundStyle(color)
                Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
            }
            Text(filing.title).font(.headline).foregroundStyle(.white).lineLimit(3)
            Text(filing.reason).font(.caption).foregroundStyle(.secondary)
            HStack {
                Label("FEED \(feedTime)", systemImage: "clock")
                Spacer()
                Text("DETECTED \(seenTime)")
                Spacer()
                if let lag = filing.lagSeconds {
                    Text("Δ \(lag)s*")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.cyan)
        }
        .padding(.vertical, 6)
    }
}
