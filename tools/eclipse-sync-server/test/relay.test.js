import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { setTimeout as delay } from 'node:timers/promises';
import { WebSocket } from 'ws';
import { createRelay, readConfig } from '../relay.js';
import { mediaIdentifier, sameMedia, stableKey, validateCommand, validateMedia } from '../protocol.js';

const movie = { tmdbID: 603, mediaType: 'movie', isAnime: false };
const anime = (context = {}) => ({ tmdbID: 46260, mediaType: 'tv', isAnime: true,
  playbackContext: { localSeasonNumber: -101, localEpisodeNumber: 3, anilistMediaId: 101,
    isSpecial: false, titleOnlySearch: false, ...context } });
const command = (type, fields = {}) => ({ protocolVersion: 1, type, ...fields });
async function eventually(predicate) {
  for (let i = 0; i < 200; i++) { if (predicate()) return; await delay(5); }
  assert.fail('condition did not become true');
}
async function fixture(t, options = {}) {
  const relay = createRelay({ ...options, config: { ...readConfig({ PORT: '0', HOST: '127.0.0.1' }), ...options.config } });
  t.after(() => relay.close());
  const address = await relay.listen();
  const url = `ws://127.0.0.1:${address.port}`;
  async function connect(options = {}) {
    const ws = new WebSocket(url, options);
    const inbox = [];
    ws.on('error', () => {});
    ws.on('message', bytes => inbox.push(JSON.parse(bytes.toString())));
    const closed = new Promise(resolve => ws.once('close', (code, reason) => resolve({ code, reason: reason.toString() })));
    await once(ws, 'open');
    return {
      ws, inbox, closed,
      send: (type, fields) => ws.send(JSON.stringify(command(type, fields))),
      async next(type) {
        await eventually(() => inbox.some(message => message.type === type));
        return inbox.splice(inbox.findIndex(message => message.type === type), 1)[0];
      },
    };
  }
  async function host(media = movie) {
    const peer = await connect(); peer.send('create_room', { media });
    const created = await peer.next('room_created');
    return { ...peer, room: created.room, sessionID: created.sessionID, media };
  }
  async function join(h, media = h.media) {
    const peer = await connect(); peer.send('join_room', { room: h.room, media });
    const joined = await peer.next('joined');
    return { ...peer, joined };
  }
  return { relay, url, connect, host, join };
}
function state(h, overrides = {}) {
  return { room: h.room, sessionID: h.sessionID, media: h.media, mediaId: mediaIdentifier(h.media),
    playing: true, position: 42.5, rate: 1, sequence: 1, sentAt: Date.now() / 1000,
    stalled: false, reason: 'heartbeat', ...overrides };
}
function scenario(name, fn) { test(name, { timeout: 5000 }, fn); }

scenario('create: cryptographic six-digit code and UUID membership', async t => {
  const f = await fixture(t), h = await f.host();
  assert.match(h.room, /^[0-9]{6}$/); assert.match(h.sessionID, /^[0-9a-f-]{36}$/);
  assert.equal(f.relay.rooms.size, 1);
});
scenario('join: matching media establishes client and notifies host', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  assert.equal(c.joined.sessionID, h.sessionID); assert.equal(c.joined.state, undefined);
  assert.equal((await h.next('participant_joined')).room, h.room);
});
scenario('invalid room: malformed and unknown codes are distinct errors', async t => {
  const f = await fixture(t), c = await f.connect();
  c.send('join_room', { room: 'abc123', media: movie });
  assert.equal((await c.next('error')).code, 'invalid_message');
  c.send('join_room', { room: '000000', media: movie });
  assert.equal((await c.next('error')).code, 'room_not_found');
});
scenario('duplicate create cannot replace a host room; random collision retries', async t => {
  const codes = ['000001', '000001', '000002'];
  const f = await fixture(t, { roomCode: () => codes.shift() ?? '000001' });
  const a = await f.host(), b = await f.host();
  assert.equal(a.room, '000001'); assert.equal(b.room, '000002');
  a.send('create_room', { media: movie }); assert.equal((await a.next('error')).code, 'invalid_message');
  assert.equal(f.relay.rooms.size, 2);
});
scenario('exhausted collisions fail boundedly and preserve existing room', async t => {
  let attempts = 0;
  const f = await fixture(t, { roomCode: () => { attempts++; return '000001'; } });
  await f.host(); const c = await f.connect(); c.send('create_room', { media: movie });
  assert.equal((await c.next('error')).code, 'rate_limited');
  assert.equal(attempts, 65); assert.equal(f.relay.rooms.size, 1);
});
scenario('host state relays canonical fields and sequence without rewriting', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  const s = state(h, { sequence: 123, reason: 'seek', rate: 1.5 });
  h.send('host_state', { state: s }); assert.deepEqual((await c.next('state')).state, s);
});
scenario('client cannot publish host state or overwrite latest snapshot', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  h.send('host_state', { state: state(h) }); await c.next('state');
  c.send('host_state', { state: state(h, { sequence: 2, position: 99 }) });
  assert.equal((await c.next('error')).code, 'host_only');
  assert.equal(f.relay.rooms.get(h.room).state.position, 42.5);
});
scenario('late join and same-connection refresh receive latest state once', async t => {
  const f = await fixture(t), h = await f.host(), s = state(h, { sequence: 17 });
  h.send('host_state', { state: s }); await eventually(() => f.relay.rooms.get(h.room).state != null);
  const c = await f.join(h); assert.deepEqual(c.joined.state, s);
  c.send('join_room', { room: h.room, media: h.media });
  assert.deepEqual((await c.next('joined')).state, s);
  assert.equal(f.relay.rooms.get(h.room).clients.size, 1);
});
scenario('aged cached state is withheld and refresh asks host for a new snapshot', async t => {
  let time = Date.now() / 1000;
  const f = await fixture(t, { epoch: () => time }), h = await f.host();
  h.send('host_state', { state: state(h, { sentAt: time }) });
  await eventually(() => f.relay.rooms.get(h.room).state != null);
  time += 21;
  const c = await f.join(h); assert.equal(c.joined.state, undefined);
  await h.next('participant_joined');
  const s = state(h, { sequence: 2, sentAt: time });
  h.send('host_state', { state: s }); assert.deepEqual((await c.next('state')).state, s);
  time += 21; c.send('join_room', { room: h.room, media: h.media });
  assert.equal((await c.next('joined')).state, undefined); await h.next('participant_joined');
});
scenario('Swift-style uppercase UUIDs and null optional fields round-trip compatibly', async t => {
  const f = await fixture(t), media = { ...movie, title: 'The Matrix', seasonNumber: null,
    episodeNumber: null, playbackContext: null }, h = await f.host(media), c = await f.join(h);
  const s = state(h, { sessionID: h.sessionID.toUpperCase() });
  h.send('host_state', { state: s });
  const relayed = (await c.next('state')).state;
  assert.equal(relayed.sessionID, h.sessionID); assert.equal(relayed.mediaId, s.mediaId);
  assert.equal(relayed.media.title, 'The Matrix'); assert.equal(relayed.media.seasonNumber, undefined);
});
scenario('host disconnect closes and deletes room', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  h.ws.terminate(); assert.equal((await c.next('room_closed')).reason, 'host_disconnected');
  await eventually(() => f.relay.rooms.size === 0);
});
scenario('client disconnect keeps host alive and reconnect receives latest state', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  const s = state(h); h.send('host_state', { state: s }); await c.next('state');
  c.ws.close(); await h.next('participant_left');
  assert.equal(f.relay.rooms.size, 1); assert.equal(h.ws.readyState, WebSocket.OPEN);
  assert.deepEqual((await f.join(h)).joined.state, s);
});
scenario('malformed JSON rejects safely and strike limit closes offender', async t => {
  const f = await fixture(t), c = await f.connect();
  for (let i = 0; i < 3; i++) { c.ws.send('{'); assert.equal((await c.next('error')).code, 'invalid_message'); }
  assert.equal((await c.closed).code, 1008); await f.host();
});
scenario('unsupported version is rejected', async t => {
  const f = await fixture(t), c = await f.connect();
  c.ws.send(JSON.stringify({ protocolVersion: 2, type: 'create_room', media: movie }));
  assert.equal((await c.next('error')).code, 'invalid_message');
});
scenario('unknown and server-only message types are rejected', async t => {
  const f = await fixture(t), c = await f.connect();
  for (const type of ['send_video', 'room_created']) { c.send(type); assert.equal((await c.next('error')).code, 'invalid_message'); }
});
scenario('oversized payload closes with 1009 and server stays available', async t => {
  const f = await fixture(t), c = await f.connect(); c.ws.send('x'.repeat(16385));
  assert.equal((await c.closed).code, 1009); await f.host();
});
scenario('idle cleanup uses host state activity, not ping activity', async t => {
  let time = 100;
  const f = await fixture(t, { monotonic: () => time, config: { roomIdleTimeout: 120 } });
  const h = await f.host(), c = await f.join(h);
  time += 119; h.send('ping', { id: randomUUID(), sentAt: Date.now() / 1000 }); await h.next('pong');
  f.relay.sweep(); assert.equal(f.relay.rooms.size, 1);
  time++; f.relay.sweep(); assert.equal((await c.next('room_closed')).reason, 'expired');
  assert.equal(f.relay.rooms.size, 0);
});
scenario('default max client limit rejects second client but permits rejoin', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h), extra = await f.connect();
  extra.send('join_room', { room: h.room, media: movie }); assert.equal((await extra.next('error')).code, 'room_full');
  c.send('join_room', { room: h.room, media: movie }); await c.next('joined');
});
scenario('duplicate/out-of-order sequences are dropped; invalid sequence rejected', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  h.send('host_state', { state: state(h, { sequence: 10 }) }); await c.next('state');
  for (const sequence of [10, 9]) h.send('host_state', { state: state(h, { sequence, position: 999 }) });
  h.send('ping', { id: randomUUID(), sentAt: Date.now() / 1000 }); await h.next('pong');
  assert.equal(c.inbox.filter(m => m.type === 'state').length, 0);
  assert.equal(f.relay.rooms.get(h.room).state.sequence, 10);
  for (const sequence of [0, Number.MAX_SAFE_INTEGER + 1]) {
    h.send('host_state', { state: state(h, { sequence }) }); assert.equal((await h.next('error')).code, 'invalid_message');
  }
});
scenario('ping/pong preserves client time and stamps ordered server times', async t => {
  const f = await fixture(t), c = await f.connect(), id = randomUUID(), sentAt = Date.now() / 1000 - 500;
  c.send('ping', { id, sentAt }); const pong = await c.next('pong');
  assert.equal(pong.id, id); assert.equal(pong.clientSentAt, sentAt);
  assert.ok(pong.serverSentAt >= pong.serverReceivedAt); assert.ok(Math.abs(pong.serverSentAt - Date.now() / 1000) < 1);
});
scenario('explicit host leave closes room; client leave releases slot', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  c.send('leave_room', { room: h.room, sessionID: h.sessionID.toUpperCase() }); await h.next('participant_left');
  const replacement = await f.join(h);
  h.send('leave_room', { room: h.room, sessionID: h.sessionID });
  assert.equal((await replacement.next('room_closed')).reason, 'host_left'); assert.equal(f.relay.rooms.size, 0);
});
scenario('room/session/media mismatch cannot mutate canonical state', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.connect();
  c.send('join_room', { room: h.room, media: { ...movie, tmdbID: 604 } });
  assert.equal((await c.next('error')).code, 'media_mismatch');
  for (const overrides of [{ room: '111111' }, { sessionID: randomUUID() }]) {
    h.send('host_state', { state: state(h, overrides) }); assert.equal((await h.next('error')).code, 'invalid_message');
  }
  const other = { ...movie, tmdbID: 604 };
  h.send('host_state', { state: state(h, { media: other, mediaId: mediaIdentifier(other) }) });
  assert.equal((await h.next('error')).code, 'media_mismatch'); assert.equal(f.relay.rooms.get(h.room).state, null);
});
scenario('future and old host timestamps fail closed', async t => {
  const f = await fixture(t), h = await f.host();
  for (const offset of [2, -21]) {
    h.send('host_state', { state: state(h, { sentAt: Date.now() / 1000 + offset }) });
    assert.equal((await h.next('error')).code, 'invalid_message');
  }
  assert.equal(f.relay.rooms.get(h.room).state, null);
});
scenario('unknown nested fields, credential fields and wrong scalar types are rejected', async t => {
  const f = await fixture(t);
  for (const payload of [
    command('create_room', { media: movie, headers: { Authorization: 'must-not-relay' } }),
    command('create_room', { media: { ...movie, streamURL: 'must-not-relay' } }),
    command('create_room', { media: anime({ subtitle: 'must-not-relay' }) }),
    command('create_room', { media: { ...movie, tmdbID: true } }),
    command('create_room', { media: anime({ localEpisodeNumber: 0 }) }),
  ]) {
    const c = await f.connect(); c.ws.send(JSON.stringify(payload));
    assert.equal((await c.next('error')).code, 'invalid_message'); c.ws.close();
  }
  assert.equal(f.relay.rooms.size, 0);
});
scenario('binary application messages are rejected', async t => {
  const f = await fixture(t), c = await f.connect(); c.ws.send(Buffer.from(JSON.stringify(command('create_room', { media: movie }))));
  assert.equal((await c.next('error')).code, 'invalid_message'); assert.equal(f.relay.rooms.size, 0);
});
scenario('max rooms rejects creation without replacing current room', async t => {
  const f = await fixture(t, { config: { maxRooms: 1 } }); await f.host();
  const c = await f.connect(); c.send('create_room', { media: movie });
  assert.equal((await c.next('error')).code, 'rate_limited'); assert.equal(f.relay.rooms.size, 1);
});
scenario('join attempts are bounded per connection', async t => {
  const f = await fixture(t), c = await f.connect();
  for (let i = 0; i < 7; i++) {
    c.send('join_room', { room: '000000', media: movie });
    assert.equal((await c.next('error')).code, i < 6 ? 'room_not_found' : 'rate_limited');
  }
  assert.equal((await c.closed).code, 1008);
});
scenario('aggregate join attempts remain bounded across connections from one IP', async t => {
  const f = await fixture(t);
  for (let i = 0; i < 13; i++) {
    const c = await f.connect(); c.send('join_room', { room: '000000', media: movie });
    assert.equal((await c.next('error')).code, i < 12 ? 'room_not_found' : 'rate_limited'); c.ws.close();
  }
});
scenario('message floods are closed without unbounded buffering', async t => {
  const f = await fixture(t), c = await f.connect();
  for (let i = 0; i < 40; i++) c.send('ping', { id: randomUUID(), sentAt: Date.now() / 1000 });
  assert.equal((await c.next('error')).code, 'rate_limited'); assert.equal((await c.closed).code, 1008);
});
scenario('health endpoint is minimal and WebSocket accepts only root without credentials', async t => {
  const f = await fixture(t);
  const health = await fetch(f.url.replace('ws:', 'http:') + '/health');
  assert.equal(health.status, 200); assert.equal(await health.text(), 'ok\n');
  assert.equal((await fetch(f.url.replace('ws:', 'http:') + '/rooms')).status, 404);
  for (const [path, headers] of [['/sync', {}], ['/?token=secret', {}], ['/', { Cookie: 'secret' }], ['/', { Authorization: 'secret' }]]) {
    const ws = new WebSocket(f.url + path, { headers }); ws.on('error', () => {});
    const [, response] = await once(ws, 'unexpected-response'); assert.equal(response.statusCode, 400);
    response.resume(); ws.terminate();
  }
});
scenario('global and IP connection caps reject excess upgrades', async t => {
  const f = await fixture(t, { config: { maxConnections: 1, maxConnectionsPerIP: 1 } }); await f.connect();
  const ws = new WebSocket(f.url); ws.on('error', () => {});
  const [, response] = await once(ws, 'unexpected-response'); assert.equal(response.statusCode, 429);
  response.resume(); ws.terminate();
});
scenario('unjoined connections expire and dead sockets are detected', async t => {
  let time = 10;
  const f = await fixture(t, { monotonic: () => time, heartbeatInterval: 20 });
  const unjoined = await f.connect(); time += 30; f.relay.sweep(); await unjoined.closed;
  const h = await f.connect({ autoPong: false });
  h.send('create_room', { media: movie }); await h.next('room_created');
  await h.closed; await eventually(() => f.relay.rooms.size === 0);
});
scenario('configuration rejects invalid/unbounded limits', () => {
  for (const env of [{ MAX_MESSAGE_BYTES: '16385' }, { MAX_ROOMS: '0' }, { PORT: 'nan' }, { ROOM_IDLE_TIMEOUT: '' }]) {
    assert.throws(() => readConfig(env));
  }
  assert.equal(readConfig({}).maxClientsPerRoom, 1);
});
scenario('movie/TV/anime identities mirror Swift stable keys and matching priority', () => {
  assert.equal(stableKey(validateMedia(movie)), 'movie:603');
  assert.equal(mediaIdentifier(movie), 'cc4609538a1537f6d0f2d3c00780703e92cd6e6bca956469b07d280d1848eade');
  assert.equal(stableKey(validateMedia({ tmdbID: 1399, mediaType: 'tv', seasonNumber: 1, episodeNumber: 2 })), 'episode:1399:1:2');
  const kitsu = anime({ kitsuMediaId: 5 });
  assert.equal(stableKey(validateMedia(kitsu)), 'anime-episode:46260:kitsu:5:3');
  const mapped = anime({ tmdbSeasonNumber: 2, tmdbEpisodeOffset: 12 });
  assert.equal(stableKey(validateMedia(mapped)), 'anime-episode:46260:tmdb:2:15');
  assert.equal(stableKey(validateMedia(anime({ anilistMediaId: -99, canonicalAniListMediaId: 101 }))), 'anime-episode:46260:provider:101:3');
  assert.ok(sameMedia(anime(), kitsu)); // Different hashes can be the same logical episode.
  assert.ok(sameMedia(anime({ anilistMediaId: -99, canonicalAniListMediaId: 101 }), anime()));
  assert.ok(sameMedia(anime({ anilistMediaId: -99 }), anime({ anilistMediaId: 101, malMediaId: 99 })));
  assert.equal(sameMedia(anime({ kitsuMediaId: 5 }), anime({ kitsuMediaId: 6 })), false);
  assert.equal(sameMedia(anime({ anilistMediaId: 102, kitsuMediaId: 5 }), kitsu), false);
  assert.equal(sameMedia(anime({ canonicalAniListMediaId: 102 }), anime({ canonicalAniListMediaId: 103 })), false);
  assert.equal(sameMedia(mapped, anime({ tmdbSeasonNumber: 2, tmdbEpisodeNumber: 16 })), false);
  assert.throws(() => validateMedia(anime({ kitsuMediaId: 0 })));
});
scenario('existing Swift anime protocol fixture matches canonical alias and digest', () => {
  // Same coordinates/IDs as EclipseSyncProtocolTests.testAnimeMatchingUsesExistingCanonicalPolicy.
  const descriptor = (rawID, episode = 5) => ({ tmdbID: 95479, mediaType: 'tv', seasonNumber: 1,
    episodeNumber: 24 + episode, isAnime: true, playbackContext: {
      localSeasonNumber: 2, localEpisodeNumber: episode, anilistMediaId: rawID,
      canonicalAniListMediaId: 145064, malMediaId: 51009, tmdbSeasonNumber: 1,
      tmdbEpisodeNumber: 24 + episode, tmdbEpisodeOffset: 24,
      animeAbsoluteEpisodeNumber: 24 + episode, animeSeasonEpisodeCount: 23,
      isSpecial: false, titleOnlySearch: false,
    } });
  const first = validateMedia(descriptor(145064)), alias = validateMedia(descriptor(999));
  assert.ok(sameMedia(first, alias)); assert.equal(sameMedia(first, validateMedia(descriptor(145064, 6))), false);
  assert.equal(mediaIdentifier(first), '8e53a85545b521f3e1f1d0db4996ccf16c9d8e41e87c5622249ecbd4dccd44d9');
});
scenario('state bounds, required fields, UUID/hash, booleans and secrets fail closed', () => {
  const h = { room: '123456', sessionID: randomUUID(), media: movie }, now = Date.now() / 1000;
  const s = state(h, { sentAt: now });
  for (const overrides of [
    { position: -1 }, { position: 604801 }, { rate: 0.24 }, { rate: 3.01 }, { sequence: 1.5 },
    { sessionID: 'invalid' }, { mediaId: 'not-sha256' }, { playing: 1 }, { stalled: 'false' },
    { reason: 'video' }, { headers: { Cookie: 'must-not-relay' } }, { sentAt: null },
  ]) assert.throws(() => validateCommand(command('host_state', { state: { ...s, ...overrides } }), now));
  const missing = { ...s }; delete missing.stalled;
  assert.throws(() => validateCommand(command('host_state', { state: missing }), now));
  assert.equal(validateCommand(command('host_state', { state: { ...s, sequence: Number.MAX_SAFE_INTEGER,
    position: 604800, rate: 3 } }), now).state.sequence, Number.MAX_SAFE_INTEGER);
});
scenario('WebSocket control-frame floods also obey message bounds', async t => {
  const f = await fixture(t), c = await f.connect();
  for (let i = 0; i < 40; i++) c.ws.pong();
  assert.equal((await c.next('error')).code, 'rate_limited'); assert.equal((await c.closed).code, 1008);
});
scenario('anime join accepts logical alias, rejects contradictory identities', async t => {
  const f = await fixture(t), h = await f.host(anime({ kitsuMediaId: 5 }));
  const c = await f.join(h, anime());
  const s = state(h); h.send('host_state', { state: s }); assert.deepEqual((await c.next('state')).state, s);
  const other = await f.connect(); other.send('join_room', { room: h.room, media: anime({ kitsuMediaId: 6 }) });
  assert.equal((await other.next('error')).code, 'media_mismatch');
});
scenario('end-to-end two clients: calibration, controls, reconnect snapshot, leave', async t => {
  const f = await fixture(t), h = await f.host(), c = await f.join(h);
  for (const peer of [h, c]) {
    peer.send('ping', { id: randomUUID(), sentAt: Date.now() / 1000 }); await peer.next('pong');
  }
  const controls = [
    { reason: 'play', playing: true, position: 5 }, { reason: 'pause', playing: false, position: 8 },
    { reason: 'seek', playing: false, position: 90 }, { reason: 'rate', playing: true, rate: 1.25, position: 90 },
    { reason: 'heartbeat', playing: true, stalled: true, position: 92 },
  ];
  for (let i = 0; i < controls.length; i++) {
    const s = state(h, { ...controls[i], sequence: i + 1 });
    h.send('host_state', { state: s }); assert.deepEqual((await c.next('state')).state, s);
  }
  c.ws.terminate(); await h.next('participant_left');
  const reconnected = await f.join(h); assert.equal(reconnected.joined.state.sequence, controls.length);
  h.send('leave_room', { room: h.room, sessionID: h.sessionID });
  assert.equal((await reconnected.next('room_closed')).reason, 'host_left'); assert.equal(f.relay.rooms.size, 0);
});
