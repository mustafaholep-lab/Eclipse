import { createHash } from 'node:crypto';

export const MAX_MESSAGE_BYTES = 16_384;
const MAX_ID = 2_147_483_647;
const MAX_COORD = 1_000_000;
const MEDIA_FIELDS = ['tmdbID', 'mediaType', 'seasonNumber', 'episodeNumber', 'playbackContext', 'isAnime', 'title'];
const CONTEXT_FIELDS = ['localSeasonNumber', 'localEpisodeNumber', 'anilistMediaId', 'canonicalAniListMediaId',
  'malMediaId', 'kitsuMediaId', 'tmdbSeasonNumber', 'tmdbEpisodeNumber', 'tmdbEpisodeOffset',
  'animeAbsoluteEpisodeNumber', 'animeSeasonEpisodeCount', 'isSpecial', 'titleOnlySearch'];
const STATE_FIELDS = ['room', 'sessionID', 'media', 'mediaId', 'playing', 'position', 'rate', 'sequence', 'sentAt', 'stalled', 'reason'];
const COMMAND_FIELDS = {
  create_room: ['media'], join_room: ['room', 'media'], leave_room: ['room', 'sessionID'],
  host_state: ['state'], ping: ['id', 'sentAt'],
};

const object = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const integer = (value, min, max) => Number.isSafeInteger(value) && value >= min && value <= max;
const finite = (value, min, max = Infinity) => typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
const optional = (value, predicate) => value == null || predicate(value);
export const validRoom = value => typeof value === 'string' && /^[0-9]{6}$/.test(value);
export const validUUID = value => typeof value === 'string' && /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value);
function requireValid(condition) { if (!condition) throw new Error('invalid_message'); }
function fields(value, allowed, required = []) {
  requireValid(object(value) && Object.keys(value).every(key => allowed.includes(key))
    && required.every(key => Object.hasOwn(value, key)));
}
function copyFields(value, allowed) {
  return Object.fromEntries(allowed.filter(key => value[key] != null).map(key => [key, value[key]]));
}

// Mirrors ProgressPersistencePolicy.sanitizedPlaybackContext; never accepts arbitrary metadata.
function validateContext(value) {
  fields(value, CONTEXT_FIELDS, ['localSeasonNumber', 'localEpisodeNumber', 'isSpecial', 'titleOnlySearch']);
  requireValid(integer(value.localSeasonNumber, -MAX_COORD, MAX_COORD)
    && integer(value.localEpisodeNumber, 1, MAX_COORD)
    && typeof value.isSpecial === 'boolean' && typeof value.titleOnlySearch === 'boolean'
    && optional(value.anilistMediaId, id => integer(id, -MAX_ID, MAX_ID) && id !== 0));
  for (const key of ['canonicalAniListMediaId', 'malMediaId', 'kitsuMediaId']) {
    requireValid(optional(value[key], id => integer(id, 1, MAX_ID)));
  }
  for (const key of ['tmdbEpisodeNumber', 'animeAbsoluteEpisodeNumber', 'animeSeasonEpisodeCount']) {
    requireValid(optional(value[key], n => integer(n, 1, MAX_COORD)));
  }
  requireValid(optional(value.tmdbSeasonNumber, n => integer(n, 0, MAX_COORD))
    && optional(value.tmdbEpisodeOffset, n => integer(n, -MAX_COORD, MAX_COORD))
    && (value.tmdbEpisodeOffset == null || integer(value.localEpisodeNumber + value.tmdbEpisodeOffset, 1, MAX_COORD)));
  return copyFields(value, CONTEXT_FIELDS);
}
const animeContext = c => c != null && [c.anilistMediaId, c.canonicalAniListMediaId, c.kitsuMediaId].some(id => id != null);
const resolvedEpisode = c => c.tmdbEpisodeNumber ?? (c.tmdbSeasonNumber != null && c.tmdbEpisodeOffset != null
  ? c.localEpisodeNumber + c.tmdbEpisodeOffset : undefined);
const positiveAniList = c => c.canonicalAniListMediaId ?? (c.anilistMediaId > 0 ? c.anilistMediaId : undefined);
const exactMAL = c => c.malMediaId ?? (c.anilistMediaId < 0 ? -c.anilistMediaId : undefined);

export function validateMedia(value) {
  fields(value, MEDIA_FIELDS, ['tmdbID', 'mediaType']);
  requireValid(integer(value.tmdbID, 1, MAX_ID) && typeof value.mediaType === 'string'
    && optional(value.isAnime, flag => typeof flag === 'boolean')
    && optional(value.title, title => typeof title === 'string' && [...new Intl.Segmenter(undefined, { granularity: 'grapheme' }).segment(title)].length <= 120));
  const media = copyFields(value, MEDIA_FIELDS);
  media.mediaType = value.mediaType.trim().toLowerCase();
  media.isAnime = value.isAnime ?? false;
  if (media.title != null) { media.title = media.title.trim(); if (!media.title) delete media.title; }
  if (media.mediaType === 'movie') {
    requireValid(value.seasonNumber == null && value.episodeNumber == null && value.playbackContext == null);
  } else {
    requireValid(media.mediaType === 'tv'
      && optional(value.seasonNumber, n => integer(n, 0, MAX_COORD))
      && optional(value.episodeNumber, n => integer(n, 1, MAX_COORD)));
    if (value.playbackContext != null) media.playbackContext = validateContext(value.playbackContext);
    if (media.isAnime || animeContext(media.playbackContext)) requireValid(animeContext(media.playbackContext));
    else requireValid(integer(media.seasonNumber, 1, MAX_COORD) && integer(media.episodeNumber, 1, MAX_COORD));
  }
  requireValid(stableKey(media) !== null);
  return media;
}

// Stable-key priority must remain identical to WatchTogetherMediaDescriptor.stableKey.
export function stableKey(media) {
  if (media.mediaType === 'movie') return `movie:${media.tmdbID}`;
  const c = media.playbackContext;
  if (!media.isAnime && !animeContext(c)) return `episode:${media.tmdbID}:${media.seasonNumber}:${media.episodeNumber}`;
  if (!animeContext(c)) return null;
  let identity;
  if (c.kitsuMediaId != null) identity = `kitsu:${c.kitsuMediaId}:${c.localEpisodeNumber}`;
  else if (c.tmdbSeasonNumber != null && resolvedEpisode(c) != null) identity = `tmdb:${c.tmdbSeasonNumber}:${resolvedEpisode(c)}`;
  else if ((positiveAniList(c) ?? c.anilistMediaId) != null) identity = `provider:${positiveAniList(c) ?? c.anilistMediaId}:${c.localEpisodeNumber}`;
  else return null;
  return `anime-episode:${media.tmdbID}:${identity}`;
}
export const mediaIdentifier = media => createHash('sha256').update(stableKey(media)).digest('hex');

// Mirrors AnimeEpisodeIdentityPolicy.isSameEpisode with its default (empty) alias map.
export function sameMedia(a, b) {
  if (a.tmdbID !== b.tmdbID || a.mediaType !== b.mediaType) return false;
  if (a.mediaType === 'movie') return true;
  const ac = a.playbackContext, bc = b.playbackContext;
  const aa = a.isAnime || animeContext(ac), ba = b.isAnime || animeContext(bc);
  if (!aa && !ba) return a.seasonNumber === b.seasonNumber && a.episodeNumber === b.episodeNumber;
  if (!aa || !ba || !ac || !bc) return false;
  const contradiction = (ac.kitsuMediaId != null && bc.kitsuMediaId != null && ac.kitsuMediaId !== bc.kitsuMediaId)
    || (ac.tmdbSeasonNumber != null && bc.tmdbSeasonNumber != null && resolvedEpisode(ac) != null && resolvedEpisode(bc) != null
      && (ac.tmdbSeasonNumber !== bc.tmdbSeasonNumber || resolvedEpisode(ac) !== resolvedEpisode(bc)));
  const sameLocalEpisode = ac.localEpisodeNumber === bc.localEpisodeNumber;
  if (ac.anilistMediaId != null && ac.anilistMediaId === bc.anilistMediaId) {
    return !(ac.canonicalAniListMediaId != null && bc.canonicalAniListMediaId != null
      && ac.canonicalAniListMediaId !== bc.canonicalAniListMediaId) && !contradiction && sameLocalEpisode;
  }
  const ap = ac.canonicalAniListMediaId ?? ac.anilistMediaId, bp = bc.canonicalAniListMediaId ?? bc.anilistMediaId;
  if (ap != null && bp != null) {
    if (ap === bp) return !contradiction && sameLocalEpisode;
    if ((ap > 0) === (bp > 0)) return false;
  }
  if (exactMAL(ac) != null && exactMAL(ac) === exactMAL(bc) && !contradiction && sameLocalEpisode) return true;
  if (ac.kitsuMediaId != null && ac.kitsuMediaId === bc.kitsuMediaId && !contradiction && sameLocalEpisode) return true;
  return ac.tmdbSeasonNumber != null && ac.tmdbSeasonNumber === bc.tmdbSeasonNumber
    && resolvedEpisode(ac) != null && resolvedEpisode(ac) === resolvedEpisode(bc) && !contradiction;
}

export function validateCommand(value, serverNow) {
  requireValid(object(value) && value.protocolVersion === 1 && typeof value.type === 'string'
    && Object.hasOwn(COMMAND_FIELDS, value.type));
  const allowed = COMMAND_FIELDS[value.type];
  fields(value, ['protocolVersion', 'type', ...allowed], allowed);
  const command = { type: value.type };
  switch (value.type) {
    case 'create_room': command.media = validateMedia(value.media); break;
    case 'join_room':
      requireValid(validRoom(value.room)); command.room = value.room; command.media = validateMedia(value.media); break;
    case 'leave_room':
      requireValid(validRoom(value.room) && validUUID(value.sessionID));
      command.room = value.room; command.sessionID = value.sessionID.toLowerCase(); break;
    case 'ping':
      requireValid(validUUID(value.id) && finite(value.sentAt, Number.MIN_VALUE));
      command.id = value.id; command.sentAt = value.sentAt; break;
    case 'host_state': {
      const s = value.state;
      fields(s, STATE_FIELDS, STATE_FIELDS);
      requireValid(validRoom(s.room) && validUUID(s.sessionID) && typeof s.playing === 'boolean'
        && typeof s.stalled === 'boolean' && finite(s.position, 0, 604_800) && finite(s.rate, 0.25, 3)
        && integer(s.sequence, 1, Number.MAX_SAFE_INTEGER) && finite(s.sentAt, Number.MIN_VALUE)
        && serverNow - s.sentAt >= -1 && serverNow - s.sentAt <= 20
        && ['heartbeat', 'play', 'pause', 'seek', 'rate'].includes(s.reason));
      const media = validateMedia(s.media);
      requireValid(s.mediaId === mediaIdentifier(media));
      command.state = { ...copyFields(s, STATE_FIELDS), sessionID: s.sessionID.toLowerCase(), media };
      break;
    }
  }
  return command;
}
