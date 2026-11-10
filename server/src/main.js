// Starts the BenchLog server. Settings come from the environment:
//   PORT            8420
//   DATA_DIR        ./data       library.sqlite, files/, and token live here
//   BENCHLOG_TOKEN  (optional)   overrides the token in DATA_DIR/token

import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createServer, VERSION } from './server.js';
import { Store } from './store.js';

const port = Number(process.env.PORT ?? 8420);
const dataDir = path.resolve(process.env.DATA_DIR ?? 'data');
mkdirSync(dataDir, { recursive: true });

const tokenFile = path.join(dataDir, 'token');
let token = process.env.BENCHLOG_TOKEN?.trim();
if (!token) {
  if (!existsSync(tokenFile)) {
    writeFileSync(tokenFile, randomBytes(24).toString('base64url') + '\n', { mode: 0o600 });
    console.log(`New library token (enter it in BenchLog > Settings > Sync): ${readFileSync(tokenFile, 'utf8').trim()}`);
    console.log(`It is saved in ${tokenFile}.`);
  }
  token = readFileSync(tokenFile, 'utf8').trim();
}

const store = new Store(path.join(dataDir, 'library.sqlite'));
const server = createServer({
  store, token, filesDir: path.join(dataDir, 'files'),
  log: (line) => console.log(new Date().toISOString(), line),
});
server.listen(port, '0.0.0.0', () => {
  console.log(`BenchLog server ${VERSION} on port ${port}, data in ${dataDir}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => { store.close(); process.exit(0); }));
}
