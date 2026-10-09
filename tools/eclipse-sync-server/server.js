import { createRelay } from './relay.js';

let relay;
try {
  relay = createRelay();
  const address = await relay.listen();
  console.log(`Eclipse Sync relay listening on port ${address.port}`);
} catch {
  console.error('Eclipse Sync relay could not start. Check configuration and port availability.');
  await relay?.close();
  process.exitCode = 1;
}
if (relay?.server.listening) {
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await relay.close();
  };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
}
