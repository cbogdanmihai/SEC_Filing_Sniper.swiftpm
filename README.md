# SEC Filing Sniper — Swift Playgrounds for iPad

Native SwiftUI app playground, **no Mac, Node.js, server, or Xcode project required**.

## Use on iPad
1. Download the repo as ZIP from GitHub (Code → Download ZIP), then unzip in Files.
2. In the Files app, rename the extracted folder to `SEC_Filing_Sniper.swiftpm` if necessary (the **folder**, not merely a GitHub repository name).
3. Open the `.swiftpm` package from Files in **Swift Playgrounds** on iPad.
4. Tap **Run App**. Allow networking if prompted.

Uses AppleProductTypes `.iOSApplication` and the `AppModule` executable target required for Swift Playgrounds app projects.

## Scope
- Native iPad UI with form, headline, link to original SEC filing, preliminary priority, feed time and local detection time
- Pulls the official SEC Latest Filings Atom feed; 15/30/60-second user-selectable polling **while app is active**
- Warns visibly on network / parser failure; no fake market data or hard-coded filings
- Fetch records persist in memory only for current app session
- No backend, no API keys, no broker integration, no background alerts

## Critical timing limitations
- EDGAR Atom timestamps do not prove the moment a filing first became publicly available, nor always its acceptance timestamp. "Δ" is feed timestamp versus detection timestamp, **not verified publication latency**.
- SEC can reject automated requests (403 / 429); never bypass rate limits. The included User-Agent is a placeholder: update it to include genuine contact details before relying on automation.
- **iPadOS suspends apps**: no guaranteed continuous polling or notifications when app is backgrounded / screen locked. No app-only workaround can ensure sub-minute background monitoring.
- Categories are quick heuristics based on form/headline, not analysis of complete filings and **not trading advice**.

If Swift Playgrounds has trouble opening a ZIP-extracted package, create a new App in Swift Playgrounds and copy the `App` Swift files into it; the manifest is compatible with the iPad app project format.
