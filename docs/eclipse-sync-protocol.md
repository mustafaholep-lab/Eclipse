# Eclipse Sync protocol v1

Eclipse Sync is a host-authoritative playback-control protocol over WSS, independent of
GroupActivities, Apple provisioning, FaceTime, and SharePlay. Each participant selects and
plays its own local stream. The v1 room has one host and at most one client. Player/UI
integration and a relay implementation are deferred; this document specifies the relay contract.

## Privacy and validation

Every JSON message has `protocolVersion: 1` and `type`. Accept only the fields specified here,
including nested media fields. Reject unknown versions, fields, invalid values, messages over
16 KiB, and non-host state publication. Do not relay arbitrary JSON or log payloads. Never send
stream/subtitle URLs or contents, provider keys, tokens, cookies, or playback request headers.
WebSocket messages use UTF-8 JSON; no binary media is transferred. Bound message frequency
and room creation/join attempts per connection/IP. Six-digit codes are temporary discovery
codes, not durable secrets; use cryptographically random codes, collision checks, and join
rate limiting. Deploy behind TLS. A relay must construct validated messages, not forward raw input.

## Media identity

`media` is the existing `WatchTogetherMediaDescriptor`: `tmdbID`, `mediaType` (`movie`/`tv`),
optional `seasonNumber`, `episodeNumber`, `playbackContext`, `title`, and `isAnime`.
`playbackContext` contains only the existing episode coordinates/IDs: `localSeasonNumber`,
`localEpisodeNumber`, optional `anilistMediaId`, `canonicalAniListMediaId`, `malMediaId`,
`kitsuMediaId`, `tmdbSeasonNumber`, `tmdbEpisodeNumber`, `tmdbEpisodeOffset`,
`animeAbsoluteEpisodeNumber`, `animeSeasonEpisodeCount`, plus `isSpecial` and `titleOnlySearch`.
Reuse `isSameLogicalMedia` / `AnimeEpisodeIdentityPolicy`; do not match on title, URL, or
duration. `mediaId` is the SHA-256 hex digest of the descriptor's existing stable key.
Different stable keys can describe the same logical anime episode; compare descriptors too.
V1 requires the existing validated TMDB identity plus anime context where applicable; no
new IMDb-only fallback is introduced. Missing/conflicting identity fails closed.

## Messages

| Direction | Type | Additional fields |
| --- | --- | --- |
| Client → server | `create_room` | `media` |
| Client → server | `join_room` | `room`, `media` |
| Client → server | `leave_room` | `room`, `sessionID` |
| Host → server | `host_state` | `state` |
| Client → server | `ping` | `id` (UUID), `sentAt` (local epoch seconds) |
| Server → host | `room_created` | `room`, `sessionID` (UUID) |
| Server → client | `joined` | `room`, `sessionID`, optional latest `state` |
| Server → peer | `participant_joined`, `participant_left` | `room`, `sessionID` |
| Server → client | `state` | `state` |
| Server → peers | `room_closed` | `room`, `sessionID`, `reason` |
| Server → client | `error` | `code` |
| Server → client | `pong` | `id`, `clientSentAt`, `serverReceivedAt`, `serverSentAt` |

Room codes are exactly six ASCII digits, including leading zeroes. `sessionID` distinguishes
a room incarnation from later reuse of its code. The server binds role/membership to the
connection; callers cannot claim host authority in a payload. On `join_room`, reject a media
mismatch before membership/state application. Rejoining the same room replaces a departed
client connection and returns the latest authoritative snapshot. `joined` without state waits
for the host's first state. An existing room incarnation must match when reconnecting.

Error codes: `room_not_found`, `room_full`, `media_mismatch`, `host_only`, `invalid_message`,
`rate_limited`. Close reasons: `host_left`, `host_disconnected`, `expired`. Unknown types are
rejected until a later protocol version defines them. Future media/episode transitions require
explicit messages and a new media revision; v1 does not silently change media or elect hosts.

## Playback state and ordering

```json
{
  "protocolVersion": 1,
  "type": "state",
  "state": {
    "room": "482731",
    "sessionID": "aaaaaaaa-0000-0000-0000-000000000000",
    "media": {"tmdbID": 603, "mediaType": "movie", "isAnime": false},
    "mediaId": "<SHA-256 hex of movie:603>",
    "playing": true,
    "position": 846.31,
    "rate": 1.0,
    "sequence": 123,
    "sentAt": 1791540000.123,
    "stalled": false,
    "reason": "heartbeat"
  }
}
```

`sequence` increases for every host publication, including heartbeats; valid range is
1...9007199254740991 (exact JavaScript integer range). Reject duplicate/out-of-order states.
Reconnect or an explicitly requested refresh permits one equal-sequence snapshot of the same room incarnation, never a lower
sequence. `position` is finite seconds in 0...604800; `rate` is finite in 0.25...3. `reason` is
`heartbeat`, `play`, `pause`, `seek`, or `rate`. Explicit seeks force correction even within
the drift tolerance. Publish controls immediately and a snapshot about every two seconds.

`sentAt` is server-clock epoch seconds, using each participant's ping/pong calibration.
Pong echoes the exact client timestamp and stamps server receipt/send times. With local
receipt T4 and timestamps T1/T2/T3, offset = ((T2-T1)+(T3-T4))/2 and RTT = (T4-T1)-(T3-T2).
Reject impossible or >5-second RTT samples; retain the lowest-RTT sample per connection.
Before calibration, retain state without applying it. Resample every ten seconds.

Project host position at reception: `position + max(0, serverNow-sentAt)*rate` only when
playing and not stalled. Reject >20-second-old or >1-second-future states; request a fresh
snapshot through rejoin if necessary. Clamp to the local playable duration when available.
Ignore drift below 0.5 seconds; tolerate 0.5...1.5 seconds without a hard seek; seek above
1.5 seconds, explicit host seeks, and initial/reconnect resync. V1 uses no rate nudging.
While a client buffers, retain only the newest state, then project it again and catch up
once ready. A paused host remains at its paused position. Remote commands carry an origin
UUID; neither synchronous nor delayed renderer callbacks may publish them again. A client
control attempt is reverted to authoritative state and never becomes host state.

## Room lifecycle and reconnect

Keep rooms and their latest state in memory. Host leave/disconnect closes and deletes the
room; delete empty rooms and expire idle rooms after 120 seconds without a host heartbeat.
Client departure does not stop the host. A client reconnects with bounded exponential
backoff (1, 2, 4, 8, 16 seconds), rejoins, requests the current snapshot, and resyncs once.
Show failure after five attempts; no silent host election. All queued sends and stale socket
callbacks are discarded when membership ends. Leave, room expiration, and protocol failure
stop timers and restore ordinary local playback ownership through the future player adapter.

## Configuration and validation

`ECLIPSE_SYNC_SERVER_URL` is a build setting, exposed as an Info.plist value and read only by
`EclipseSyncConfiguration`. Set it in ignored `Build.local.xcconfig`, for example
`ECLIPSE_SYNC_SERVER_URL = wss:/$()/sync.example.com/ws`. WSS is required except loopback WS
in debug builds. No endpoint is supplied by default; no connection is opened at app startup.

Run `EclipseSyncProtocolTests`, `EclipseSyncCoordinatorTests`, and `EclipseSyncTransportTests`
with the existing `Eclipse` scheme / `Tests` target on an iOS simulator. Also run existing
subtitle, AnimeSub/Stremio, lifecycle recovery, and SharePlay protocol regression tests.
Two-iPhone and real-relay testing remain prerequisites after player integration is approved.
