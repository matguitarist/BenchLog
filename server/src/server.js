// The HTTP API. Every route but /v1/health needs `Authorization: Bearer <token>`.
//
//   GET  /v1/health                      {ok, version}
//   GET  /v1/library                     {libraryId, rows, files, cursor, numbers}
//   POST /v1/library    {libraryId}      claims an empty server for a library
//   POST /v1/push       {rows: [...]}    {applied, kept, cursor}
//   GET  /v1/pull?after=N&limit=M        {rows, cursor, more}
//   POST /v1/numbers/:name  {count}      {first, count}         ticket | invoice | credit
//   POST /v1/numbers/:name/start {atLeast}  {next}
//   PUT  /v1/files/:id   (X-Sha256)      stores an attachment's bytes
//   GET  /v1/files/:id                   the bytes, with X-Sha256
//   HEAD /v1/files/:id                   200 when stored

import { createHash, timingSafeEqual } from 'node:crypto';
import { createReadStream, createWriteStream, mkdirSync, renameSync, rmSync } from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { checkID, StoreError } from './store.js';

export const VERSION = '2.0.0';
const MAX_JSON = 32 * 1024 * 1024;
const MAX_FILE = 1024 * 1024 * 1024;

/**
 * @param {{store: import('./store.js').Store, token: string, filesDir: string, log?: (line: string) => void}} options
 */
export function createServer({ store, token, filesDir, log = () => {} }) {
  mkdirSync(filesDir, { recursive: true });
  const expected = createHash('sha256').update(token).digest();

  function authorized(req) {
    const header = req.headers.authorization ?? '';
    if (!header.startsWith('Bearer ')) return false;
    const given = createHash('sha256').update(header.slice(7)).digest();
    return timingSafeEqual(given, expected);
  }

  return http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://server');
    const parts = url.pathname.split('/').filter(Boolean);
    const started = Date.now();
    try {
      if (parts[0] !== 'v1') throw new StoreError('not found', 404);
      if (req.method === 'GET' && parts[1] === 'health' && parts.length === 2) {
        return json(res, 200, { ok: true, version: VERSION });
      }
      if (!authorized(req)) throw new StoreError('the token is missing or wrong', 401);

      switch (`${req.method} ${parts[1]}`) {
        case 'GET library':
          return json(res, 200, store.info());
        case 'POST library': {
          const body = await readJSON(req);
          return json(res, 200, { libraryId: store.claim(body.libraryId) });
        }
        case 'POST push': {
          const body = await readJSON(req);
          return json(res, 200, store.push(body.rows));
        }
        case 'GET pull': {
          const after = Number(url.searchParams.get('after') ?? 0);
          const limit = Number(url.searchParams.get('limit') ?? 500);
          if (!Number.isInteger(after) || after < 0 || !Number.isInteger(limit)) throw new StoreError('after and limit must be integers');
          return json(res, 200, store.pull(after, limit));
        }
        case 'POST numbers': {
          const body = await readJSON(req);
          if (parts[3] === 'start') return json(res, 200, { next: store.startAt(parts[2], body.atLeast) });
          if (parts.length !== 3) throw new StoreError('not found', 404);
          return json(res, 200, store.take(parts[2], body.count ?? 1));
        }
        case 'PUT files':
          return await putFile(req, res, parts[2]);
        case 'GET files':
        case 'HEAD files':
          return getFile(req, res, parts[2]);
        default:
          throw new StoreError('not found', 404);
      }
    } catch (error) {
      const status = error instanceof StoreError ? error.status : 500;
      if (status === 500) log(`error ${req.method} ${url.pathname}: ${error.stack ?? error}`);
      if (!res.headersSent) json(res, status, { error: status === 500 ? 'server error' : error.message });
      else res.destroy();
    } finally {
      log(`${req.method} ${url.pathname} ${res.statusCode} ${Date.now() - started} ms`);
    }
  });

  async function putFile(req, res, id) {
    checkID(id);
    const sha256 = String(req.headers['x-sha256'] ?? '').toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(sha256)) throw new StoreError('X-Sha256 is missing or malformed');
    const temp = path.join(filesDir, `.${id}.${process.pid}.${Date.now()}`);
    const hash = createHash('sha256');
    let size = 0;
    try {
      await pipeline(req, async function* (source) {
        for await (const chunk of source) {
          size += chunk.length;
          if (size > MAX_FILE) throw new StoreError('the file is too large', 413);
          hash.update(chunk);
          yield chunk;
        }
      }, createWriteStream(temp));
      if (hash.digest('hex') !== sha256) throw new StoreError('the file does not match its SHA-256', 422);
      renameSync(temp, path.join(filesDir, id));
    } finally {
      rmSync(temp, { force: true });
    }
    store.recordFile(id, sha256, size);
    json(res, 200, { id, sha256, size });
  }

  function getFile(req, res, id) {
    const record = store.fileRecord(id);
    if (!record) throw new StoreError('no such file', 404);
    res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': record.size, 'X-Sha256': record.sha256 });
    if (req.method === 'HEAD') return res.end();
    createReadStream(path.join(filesDir, record.id)).pipe(res);
  }
}

function json(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(text) });
  res.end(text);
}

async function readJSON(req) {
  let size = 0;
  const chunks = [];
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_JSON) throw new StoreError('the request is too large', 413);
    chunks.push(chunk);
  }
  if (size === 0) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new StoreError('the body is not JSON');
  }
}
