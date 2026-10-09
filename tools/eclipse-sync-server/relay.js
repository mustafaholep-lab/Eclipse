import http from 'node:http';
import { randomInt, randomUUID } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { WebSocket, WebSocketServer } from 'ws';
import { MAX_MESSAGE_BYTES, sameMedia, validateCommand, validRoom } from './protocol.js';

export function readConfig(env = process.env) {
  function number(name, fallback, min, max) {
    const raw = env[name];
    const value = raw === undefined ? fallback : Number(raw);
    if (!Number.isSafeInteger(value) || value < min || value > max || raw === '') throw new Error(`Invalid ${name}`);
    return value;
  }
  return {
    port: number('PORT', 8787, 0, 65535), host: env.HOST || '0.0.0.0',
    roomIdleTimeout: number('ROOM_IDLE_TIMEOUT', 120, 1, 3600),
    maxRooms: number('MAX_ROOMS', 1000, 1, 10000),
    maxClientsPerRoom: number('MAX_CLIENTS_PER_ROOM', 1, 1, 16),
    maxMessageBytes: number('MAX_MESSAGE_BYTES', MAX_MESSAGE_BYTES, 512, MAX_MESSAGE_BYTES),
    maxConnections: number('MAX_CONNECTIONS', 3000, 1, 100000),
    maxConnectionsPerIP: number('MAX_CONNECTIONS_PER_IP', 50, 1, 100000),
    invalidMessageLimit: number('INVALID_MESSAGE_LIMIT', 3, 1, 10),
  };
}

class Bucket {
  constructor(capacity, perSecond, now) { this.capacity = capacity; this.rate = perSecond; this.tokens = capacity; this.updated = now; }
  take(now) {
    this.tokens = Math.min(this.capacity, this.tokens + Math.max(0, now - this.updated) * this.rate);
    this.updated = now;
    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

// Time/code injection and sweep are used by tests; production defaults use monotonic time and crypto.
export function createRelay({ config = readConfig(), epoch = () => Date.now() / 1000,
  monotonic = () => performance.now() / 1000, roomCode = () => String(randomInt(1_000_000)).padStart(6, '0'),
  sweepInterval = 1000, heartbeatInterval = 15000 } = {}) {
  const rooms = new Map(), peers = new Map(), ips = new Map();
  let stopping = false;
  const server = http.createServer({ maxHeaderSize: 8192, requestTimeout: 10000, headersTimeout: 10000 }, (request, response) => {
    // No access logging, body parsing, credentials, room codes, or media exposed over HTTP.
    const healthy = request.method === 'GET' && request.url === '/health';
    response.writeHead(healthy ? 200 : 404, { 'Content-Type': 'text/plain', 'Cache-Control': 'no-store' });
    response.end(healthy ? 'ok\n' : 'not found\n');
  });
  server.maxConnections = config.maxConnections + 32;
  const wss = new WebSocketServer({ noServer: true, maxPayload: config.maxMessageBytes,
    perMessageDeflate: false, closeTimeout: 2000, maxFragments: 128, maxBufferedChunks: 1024 });

  function send(peer, type, fields = {}) {
    if (peer.ws.readyState !== WebSocket.OPEN) return;
    const text = JSON.stringify({ protocolVersion: 1, type, ...fields });
    if (Buffer.byteLength(text) > config.maxMessageBytes || peer.ws.bufferedAmount > 65536) {
      peer.ws.terminate(); return;
    }
    peer.ws.send(text, error => { if (error) peer.ws.terminate(); });
  }
  function reject(peer, code = 'invalid_message', strike = true) {
    send(peer, 'error', { code });
    if (strike && ++peer.strikes >= config.invalidMessageLimit) peer.ws.close(1008, 'Policy violation');
  }
  function rateLimited(peer) { send(peer, 'error', { code: 'rate_limited' }); peer.ws.close(1008, 'Rate limit'); }
  function membership(room) { return { room: room.code, sessionID: room.sessionID }; }
  function notify(room, type, except) {
    for (const peer of [room.host, ...room.clients]) if (peer !== except) send(peer, type, membership(room));
  }
  function closeRoom(room, reason) {
    if (rooms.get(room.code) !== room) return;
    rooms.delete(room.code);
    for (const peer of [room.host, ...room.clients]) {
      peer.room = null;
      send(peer, 'room_closed', { ...membership(room), reason });
      peer.ws.close(1000, 'Room closed');
    }
    room.clients.clear(); room.state = null;
  }
  function leave(peer, reason = 'host_disconnected') {
    const room = peer.room;
    peer.room = null;
    if (!room) return;
    if (room.host === peer) closeRoom(room, reason);
    else if (room.clients.delete(peer)) notify(room, 'participant_left', peer);
  }
  function handle(peer, message, receivedAt) {
    switch (message.type) {
      case 'ping':
        send(peer, 'pong', { id: message.id, clientSentAt: message.sentAt,
          serverReceivedAt: receivedAt, serverSentAt: Math.max(receivedAt, epoch()) });
        break;
      case 'create_room': {
        if (peer.room) { reject(peer); break; }
        if (rooms.size >= config.maxRooms) { reject(peer, 'rate_limited', false); break; }
        let code;
        for (let attempt = 0; attempt < 64; attempt++) {
          const candidate = roomCode();
          if (validRoom(candidate) && !rooms.has(candidate)) { code = candidate; break; }
        }
        if (!code) { reject(peer, 'rate_limited', false); break; }
        const room = { code, sessionID: randomUUID(), host: peer, clients: new Set(), media: message.media,
          state: null, lastHostActivity: monotonic() };
        peer.room = room; rooms.set(code, room);
        send(peer, 'room_created', membership(room));
        break;
      }
      case 'join_room': {
        const room = rooms.get(message.room);
        if (peer.room && (peer.room !== room || room.host === peer)) { reject(peer); break; }
        if (!room) { reject(peer, 'room_not_found', false); break; }
        if (!sameMedia(room.media, message.media)) { reject(peer, 'media_mismatch', false); break; }
        const rejoin = room.clients.has(peer);
        if (!rejoin && room.clients.size >= config.maxClientsPerRoom) { reject(peer, 'room_full', false); break; }
        peer.room = room; room.clients.add(peer);
        const fresh = room.state && receivedAt - room.state.sentAt >= -1 && receivedAt - room.state.sentAt <= 20;
        send(peer, 'joined', { ...membership(room), ...(fresh ? { state: room.state } : {}) });
        // Same-connection rejoin requests a fresh heartbeat too, especially if cached state is old.
        if (rejoin) send(room.host, 'participant_joined', membership(room));
        else notify(room, 'participant_joined', peer);
        break;
      }
      case 'leave_room':
        if (!peer.room || peer.room.code !== message.room || peer.room.sessionID !== message.sessionID) { reject(peer); break; }
        leave(peer, 'host_left');
        break;
      case 'host_state': {
        const room = peer.room;
        if (!room || room.host !== peer) { reject(peer, 'host_only'); break; }
        const state = message.state;
        if (state.room !== room.code || state.sessionID !== room.sessionID) { reject(peer); break; }
        if (!sameMedia(room.media, state.media)) { reject(peer, 'media_mismatch', false); break; }
        // Drop stale publications without touching canonical state or extending room lifetime.
        if (room.state && state.sequence <= room.state.sequence) break;
        room.state = state; room.lastHostActivity = monotonic();
        for (const client of room.clients) send(client, 'state', { state });
        break;
      }
    }
  }

  function sweep() {
    const now = monotonic();
    for (const room of rooms.values()) {
      if (room.host.ws.readyState !== WebSocket.OPEN) closeRoom(room, 'host_disconnected');
      else if (now - room.lastHostActivity >= config.roomIdleTimeout) closeRoom(room, 'expired');
    }
    for (const peer of peers.values()) if (!peer.room && now - peer.connectedAt >= 30) peer.ws.terminate();
    for (const [address, ip] of ips) if (ip.active === 0 && now - ip.lastSeen >= 60) ips.delete(address);
  }
  server.on('upgrade', (request, socket, head) => {
    socket.on('error', () => {});
    function deny(status) {
      socket.write(`HTTP/1.1 ${status}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`);
      socket.destroySoon();
    }
    // Only transport handshake headers are needed; never accept app credentials, cookies, or query tokens.
    if (stopping || request.method !== 'GET' || request.url !== '/' || request.headers.authorization
      || request.headers.cookie || request.headers['proxy-authorization']) { deny('400 Bad Request'); return; }
    const address = request.socket.remoteAddress, now = monotonic();
    sweep();
    let ip = ips.get(address);
    if (!ip) {
      if (ips.size >= config.maxConnections * 2) { deny('429 Too Many Requests'); return; }
      ip = { active: 0, lastSeen: now, connections: new Bucket(20, 1, now),
        joins: new Bucket(12, 0.2, now), messages: new Bucket(200, 100, now) };
      ips.set(address, ip);
    }
    ip.lastSeen = now;
    if (peers.size >= config.maxConnections || ip.active >= config.maxConnectionsPerIP || !ip.connections.take(now)) {
      deny('429 Too Many Requests'); return;
    }
    wss.handleUpgrade(request, socket, head, ws => {
      const peer = { ws, ip, room: null, strikes: 0, alive: true, connectedAt: now,
        messages: new Bucket(30, 10, now), joins: new Bucket(6, 0.1, now) };
      peers.set(ws, peer); ip.active++;
      ws.on('error', () => {}); // ws closes invalid frames/UTF-8 and oversized messages itself (1009).
      function controlAllowed() {
        if (ws.readyState !== WebSocket.OPEN) return false;
        const time = monotonic();
        ip.lastSeen = time;
        if (!peer.messages.take(time) || !ip.messages.take(time)) { rateLimited(peer); return false; }
        return true;
      }
      ws.on('pong', () => { if (controlAllowed()) peer.alive = true; });
      ws.on('ping', controlAllowed);
      ws.on('close', () => { leave(peer); peers.delete(ws); ip.active--; ip.lastSeen = monotonic(); });
      ws.on('message', (data, binary) => {
        if (ws.readyState !== WebSocket.OPEN) return;
        const time = monotonic(), receivedAt = epoch();
        ip.lastSeen = time;
        if (!peer.messages.take(time) || !ip.messages.take(time)) { rateLimited(peer); return; }
        if (binary || data.length > config.maxMessageBytes) { reject(peer); return; }
        let command;
        try { command = validateCommand(JSON.parse(data.toString('utf8')), receivedAt); }
        catch { reject(peer); return; }
        if (['create_room', 'join_room'].includes(command.type) && (!peer.joins.take(time) || !ip.joins.take(time))) {
          rateLimited(peer); return;
        }
        handle(peer, command, receivedAt);
      });
    });
  });
  const cleanup = setInterval(sweep, sweepInterval);
  const heartbeat = setInterval(() => {
    for (const peer of peers.values()) {
      if (!peer.alive) { peer.ws.terminate(); continue; }
      if (peer.ws.readyState === WebSocket.OPEN) { peer.alive = false; peer.ws.ping(undefined, undefined, error => { if (error) peer.ws.terminate(); }); }
    }
  }, heartbeatInterval);
  cleanup.unref(); heartbeat.unref();

  return {
    server, rooms, sweep,
    listen: () => new Promise((resolve, reject) => {
      const failed = error => { server.off('listening', ready); reject(error); };
      const ready = () => { server.off('error', failed); resolve(server.address()); };
      server.once('error', failed); server.once('listening', ready);
      server.listen(config.port, config.host);
    }),
    close: async () => {
      stopping = true; clearInterval(cleanup); clearInterval(heartbeat);
      for (const room of rooms.values()) closeRoom(room, 'host_disconnected');
      for (const peer of peers.values()) peer.ws.terminate();
      await new Promise(resolve => wss.close(resolve));
      if (server.listening) await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); });
      ips.clear();
    },
  };
}
