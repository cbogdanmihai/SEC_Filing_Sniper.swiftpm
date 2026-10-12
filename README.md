# SEC Filing Sniper

Fast, minimal EDGAR filing monitor designed for an iPad screen.

## Run locally
Requires Node.js 20+.

```bash
npm start
```

Open http://localhost:3000 (or http://YOUR-SERVER-IP:3000 on your iPad).

## Features
- SEC latest-filings Atom feed, polled by the server every 15 seconds (configurable)
- Server-sent events for near-immediate browser updates
- Newest-first feed with form, company, ticker when resolvable, source timestamp, first-detected timestamp, and measured age
- Fast heuristic classification: positive, negative, review (not a trade recommendation)
- Direct SEC link, browser sound notification when tab is open
- Health endpoint and visible source failures, without fake live results
- Lightweight installable PWA shell for iPad

## Production notes
- A **continuously running Node server** is required for continuous monitoring; static hosting and a backgrounded iPad alone are insufficient.
- HTTPS is needed for iPad home-screen PWA installation outside localhost.
- The SEC Atom 'updated' time is NOT guaranteed to equal filing acceptance or first public availability. The app labels it **Feed time** and separately records when our service detected it. A later version can enrich accepted timestamps from filing headers.
- SEC can throttle or block automated traffic. Set `SEC_USER_AGENT="SEC Filing Sniper contact@example.com"` with a real email and follow SEC fair-access policies; no guaranteed 15-second publication latency.
- Alerts in this MVP are in-page sound/visual only, **not remote push notifications when iPad is asleep**.
- By default the feed is all forms; set `SEC_FORMS="8-K,6-K,424B5,SC 13D,4"` to filter.
- The ticker is only displayed if the feed includes a verified symbol, otherwise shown as a company name; never guessed.
- This is not a real-time exchange data source or auto-execution service.

## Config
`PORT=3000`, `POLL_MS=15000` (minimum 10000), `SEC_USER_AGENT`, `SEC_FORMS`.

## Deploy
Deploy to a persistent Node host with HTTPS reverse proxy. The health check is `/api/health`. Avoid platforms that suspend background servers.
