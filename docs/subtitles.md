# Subtitle system

## Architecture

`SubtitleMetadataResolver` builds a `SubtitleQuery` from the active `PlaybackRequest`. The query carries media kind, ID families, episode coordinates, title variants, filename, release name, hash, size, and language preferences. The resolver reuses `AniListService` and AniMap episode offsets; its metadata cache contains series identity only, while the current playback request supplies episode and release details.

`SubtitleProvider` exposes `search` and `download`. `SubtitleProviderSearchCoordinator` searches enabled direct providers concurrently, publishes each completed provider batch, records valid empty results separately from failures, and limits transient retries. `SubtitleRanking` scores hash, season/episode or absolute episode, release similarity, language, and machine translation. `SubtitleFileHandling` validates, decodes, and extracts SRT/VTT/ASS/SSA files. `SubtitleDocument` extracts timed cues and dialogue previews while retaining their original formatted text. `PlayerViewController` integrates these results with the existing subtitle menu, manual search, embedded tracks, local import, selection guards, and delay controls.

## Metadata and anime episodes

Normal series queries use their season/episode. Anime queries also retain the anime's local episode and absolute episode; these may differ from the parent TMDB show's coordinates. AniList romaji, English, native, and synonym titles are available to manual search and provider queries. AniList, MAL, Kitsu, IMDb, and TMDB IDs are kept as distinct families. Manual absolute-episode edits override only the anime episode coordinate unless season/episode are explicitly edited too.

## Providers and ranking

Stremio subtitle addons are queried only when their manifest advertises the `subtitles` resource for the relevant `series`, `anime`, or `movie` type. The request planner preserves episode coordinates for each supported ID family. AnimeSub+ uses this general Stremio path. A valid `200` response with an empty subtitle list is a normal provider-empty outcome. The configured AnimeSub+ server returned empty Turkish results in some verification cases; no AnimeSub+ specific workaround is present.

Direct providers are OpenSubtitles.com (API key; optional bearer token for downloads), SubDL (API key), and Jimaku (API key). Their credentials use the existing Keychain store. The Stremio OpenSubtitles v3 addon is a separate addon path. Coverage and current availability depend on external services. Ranking favors video-hash and matching episode evidence, then release details and language; machine-translated candidates are penalized. A candidate for a different episode is filtered unless there is matching video-hash evidence.

## Adding a provider

Implement `SubtitleProvider` with a stable `id`, `supportsAnime`, `search(_:) -> [SubtitleCandidate]`, and `download(_:) -> Data`. Populate candidate language, release, format, and any trustworthy hash or quality evidence. Register and enable it through `SubtitleProviderConfiguration`, store secrets in `SubtitleProviderCredentialStore`, and add deterministic planner/ranking tests. Do not put private URLs or tokens into diagnostics.

## Diagnostics and limitations

Debug builds expose **Subtitle diagnostics** from the existing subtitle menu. It summarizes the resolved query, provider outcomes and durations, candidate scores/reasons. URLs, tokens, credentials, and dialogue are redacted. The direct-provider menu previews a few real dialogue lines using `SubtitleDocument`; downloaded preview data is reused when selected, and sign/karaoke/style events are excluded.

Provider coverage depends on external services. Live provider availability is not guaranteed. Two-point sync and `sub-speed` presets are not implemented. Device testing is still required for renderer behavior, embedded tracks, and third-party server responses.
