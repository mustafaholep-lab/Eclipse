# Eclipse Sync relay

Small Node.js WebSocket relay for the existing Eclipse Sync protocol v1. One host and one
client per room by default. Rooms, membership and the latest playback snapshot live only
in process memory. No database, account system, playback history, media proxy or provider
integration. The server accepts only the documented playback/identity fields and constructs
validated output. It never logs payloads, codes, media, IP addresses, credentials or stack
traces. Standard HTTP/WebSocket handshake headers are necessary for the transport; cookie
and authorization handshakes, query parameters and unknown application fields are rejected.

## Install and run

Requires Node.js 22 or newer with npm. From the repository root:

```sh
cd tools/eclipse-sync-server
npm install
npm test
npm run check
npm start
```

Use `npm ci --ignore-scripts` for reproducible deployment from the included lockfile. No
TypeScript compilation or native addons are required. The sole runtime dependency is `ws`.
The process listens on port 8787 by default; SIGINT/SIGTERM closes rooms and sockets.

```sh
curl http://127.0.0.1:8787/health
# 200 OK, body: ok
```

The WebSocket endpoint is **`/`**, so use `ws://127.0.0.1:8787` locally or
`wss://YOUR_TLS_HOST` behind TLS. `/sync` and `/ws` are not endpoints. `/health` returns
only liveness, with no room listing or metadata.

## Configuration

All numeric settings are integers. Invalid settings fail startup with a generic error.

| Variable | Default | Allowed range / meaning |
| --- | --- | --- |
| `PORT` | `8787` | 0–65535 (0 chooses a free port, intended for tests) |
| `HOST` | `0.0.0.0` | Bind address; use `127.0.0.1` when behind a local reverse proxy |
| `ROOM_IDLE_TIMEOUT` | `120` | 1–3600 **seconds** without an accepted, newer host state |
| `MAX_ROOMS` | `1000` | 1–10000 |
| `MAX_CLIENTS_PER_ROOM` | `1` | 1–16, excluding host; retain 1 for the supported two-user v1 experience |
| `MAX_MESSAGE_BYTES` | `16384` | 512–16384; retain default for client compatibility |
| `MAX_CONNECTIONS` | `3000` | 1–100000, includes connections without rooms |
| `MAX_CONNECTIONS_PER_IP` | `50` | 1–100000 |
| `INVALID_MESSAGE_LIMIT` | `3` | 1–10 strikes before policy close |

Additional fixed bounds: each connection gets a 30-message burst replenished at 10/sec;
each socket IP gets a 200-message burst replenished at 100/sec. Create/join attempts get
6/connection and 12/IP bursts, replenished at 6/min and 12/min respectively. Handshake
attempts get a 20/IP burst replenished at 1/sec. Limits return `rate_limited` then close
the socket, or HTTP 429 before upgrade. Anonymous sockets expire after 30 seconds.
WebSocket control ping/pong probes run every 15 seconds and terminate an unresponsive
peer on the next probe. Payloads, fragmentation and outbound buffers are bounded;
oversized messages close with 1009, repeated invalid commands with 1008. Code collisions
retry at most 64 times. IP bookkeeping is bounded and expires after 60 seconds without
connections or activity. Per-IP limits use the TCP peer address; forwarded headers are
not trusted. Behind a proxy, these limits therefore apply to the proxy collectively;
set capacity appropriately and apply end-user connection/attempt limits at the edge.

Room codes are cryptographically generated six ASCII digits with leading zeroes allowed.
They are temporary discovery codes, not authentication. Host departure closes the room;
there is no host election. Client departure frees its slot and leaves the host playing.
Do not replace an active client connection just because another caller knows its code.
After transport disconnect and slot release, reconnect/rejoin returns the latest fresh
snapshot. Same-connection rejoin is idempotent and also requests a host heartbeat through
`participant_joined`; it does not add another participant. Cached snapshots outside the
client's −1…20-second age window are withheld until a fresh host state arrives. Pings and
duplicate/out-of-order host sequences do not extend room lifetime. Full capacity/collision
exhaustion returns the existing protocol's `rate_limited` error.

## Point Eclipse at this relay

`EclipseSyncConfiguration` reads `ECLIPSE_SYNC_SERVER_URL` from the process environment
(e.g. an Xcode scheme variable), otherwise from the build setting exposed in Info.plist.
There is no default production URL. URLs cannot contain credentials, query or fragment.

For a Debug iOS simulator on the **same Mac as the server**, set the Xcode scheme variable:

```text
ECLIPSE_SYNC_SERVER_URL = ws://127.0.0.1:8787
```

Clear that scheme override when switching to devices. A physical phone's loopback is
the phone itself. The client allows unencrypted WS only on loopback in Debug; a plain
`ws://192.168.x.x:8787` LAN endpoint is intentionally rejected. Two physical iPhones
require a reachable **WSS** endpoint with a certificate both devices trust.

In ignored `Build.local.xcconfig`, the equivalent WSS build setting is:

```text
ECLIPSE_SYNC_SERVER_URL = wss:/$()/YOUR_TLS_HOST
```

The `$()` keeps Xcode from treating `//` as a comment. In a scheme environment variable
use ordinary `wss://YOUR_TLS_HOST`. Do not append a path. Rebuild/install on both phones
after changing the build setting; the setting is not an in-app URL editor.

## Local two-iPhone testing

1. Run the relay on your development machine. Expose its HTTP port through a TLS reverse
   proxy reachable by both phones, or a separately approved WSS-capable development tunnel.
   For LAN testing use a hostname resolving to the development machine and a trusted TLS
   certificate. Allow the proxy's TLS port through the firewall. Keep the relay port private.
2. Set both app builds to `wss://YOUR_TLS_HOST` as described above. Verify HTTPS `/health`
   from the same network as the phones. Proxy WebSocket Upgrade and preserve the root path.
3. On each phone choose the same movie/episode and resolve its stream locally. Host:
   Watch Together → Eclipse Sync → Create Room. Client: Join Room with the six-digit code.
4. Check immediate host play/pause/seek/rate, two-second heartbeats, client control rejection,
   buffering catch-up, network disconnect/rejoin, mismatch errors, and host leave. Different
   streams/subtitles are allowed. Confirm Apple SharePlay still works after leaving Sync.

No tunnel, paid host or public deployment is provisioned by these instructions/tests.
Node tests exercise real local WebSocket clients, not the iOS renderer, Apple SharePlay,
TLS trust or on-device network conditions. Those need Xcode and physical-device validation.

For example, an optional Caddy LAN proxy can use this development-only Caddyfile:

```caddyfile
eclipse-sync.home.arpa {
    tls internal
    reverse_proxy 127.0.0.1:8787
}
```

Resolve this example hostname to your machine's LAN IP on both phones, install and trust
the proxy's development root CA on both devices, and use `wss://eclipse-sync.home.arpa`.
Run the separately installed proxy with `caddy run --config Caddyfile`; do not expose this
development CA setup publicly. Caddy supports WebSocket upgrades through
[reverse_proxy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy), and
[`tls internal`](https://caddyserver.com/docs/caddyfile/directives/tls) uses its local CA.

## Generic production deployment

Deploy this directory to a Node host (Railway, Render, Fly.io, VPS or equivalent), install
with `npm ci --ignore-scripts`, and start with `npm start`. Pass its assigned `PORT`, bind
to `0.0.0.0` when required by the platform, and terminate TLS at its WebSocket-capable edge.
Use `GET /health` as the liveness probe. Do not use a serverless host that ends long-lived
connections after each HTTP request. Configure proxy WebSocket idle timeouts above the
15-second probe interval and allow long-lived upgrades.

Use **one process/one replica**. Rooms are not shared across workers or replicas; restart
loses all rooms. Horizontal scaling needs routing/shared state designed in a later phase.
Disable request/payload logging for the relay at the proxy/platform too. Keep its plaintext
port behind the TLS edge/firewall. No provider token or stream header belongs in relay
environment variables. Configure the final approved hostname in the client only after the
deployment is ready. No real production hostname is included here.

## Tests

`npm test` uses Node's test runner, ephemeral loopback HTTP servers and real `ws` clients.
It covers creation/collision/capacity, membership, host authority, canonical state/ordering,
late join and reconnect, host/client leave/disconnect, expiry, malformed/unknown/oversized
messages, clock calibration, nested-field privacy, rate limits, health/handshake rejection,
and anime identity parity with the Swift policy. The end-to-end scenario calibrates two
participants, relays play/pause/seek/rate/heartbeat, reconnects the client, and closes the room.
`npm run check` performs JavaScript syntax checks; there is no build step.
