// The library on the server: rows it stores without knowing their columns, number
// sequences, and file records. Last writer wins per row, by `updatedAt`.

import { DatabaseSync } from 'node:sqlite';

const TABLE = /^[A-Za-z][A-Za-z0-9]{0,63}$/;
const ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;   // never "." or "..": ids name files
/** Sequences the server hands out. */
export const SEQUENCES = ['ticket', 'invoice', 'credit'];

export class StoreError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

export class Store {
  /** @param {string} file  the SQLite file, or ':memory:' */
  constructor(file) {
    this.db = new DatabaseSync(file);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS row (
        tbl TEXT NOT NULL,
        id TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        deletedAt TEXT,
        data TEXT NOT NULL,
        seq INTEGER NOT NULL,
        PRIMARY KEY (tbl, id)
      );
      CREATE UNIQUE INDEX IF NOT EXISTS row_seq ON row(seq);
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS sequence (name TEXT PRIMARY KEY, next INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS file (
        id TEXT PRIMARY KEY,
        sha256 TEXT NOT NULL,
        size INTEGER NOT NULL,
        storedAt TEXT NOT NULL
      );
    `);
    for (const name of SEQUENCES) {
      this.db.prepare('INSERT OR IGNORE INTO sequence (name, next) VALUES (?, 1)').run(name);
    }
    this.find = this.db.prepare('SELECT updatedAt FROM row WHERE tbl = ? AND id = ?');
    this.upsert = this.db.prepare(`
      INSERT INTO row (tbl, id, updatedAt, deletedAt, data, seq) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT (tbl, id) DO UPDATE SET updatedAt = excluded.updatedAt, deletedAt = excluded.deletedAt,
        data = excluded.data, seq = excluded.seq`);
    this.since = this.db.prepare('SELECT tbl, id, updatedAt, deletedAt, data, seq FROM row WHERE seq > ? ORDER BY seq LIMIT ?');
  }

  close() { this.db.close(); }

  /** The last sequence number given to a row: what a client's cursor catches up to. */
  cursor() {
    return Number(this.db.prepare('SELECT COALESCE(MAX(seq), 0) AS seq FROM row').get().seq);
  }

  /** What the server holds, for a client deciding whether to upload or to join. */
  info() {
    const rows = Number(this.db.prepare('SELECT count(*) AS n FROM row').get().n);
    const files = Number(this.db.prepare('SELECT count(*) AS n FROM file').get().n);
    const libraryId = this.db.prepare("SELECT value FROM meta WHERE key = 'libraryId'").get()?.value ?? null;
    return { libraryId, rows, files, cursor: this.cursor(), numbers: this.numbers() };
  }

  /** Names the library the first time a client uploads; later clients must match it. */
  claim(libraryId) {
    if (typeof libraryId !== 'string' || !ID.test(libraryId)) throw new StoreError('libraryId is missing or malformed');
    const current = this.db.prepare("SELECT value FROM meta WHERE key = 'libraryId'").get()?.value;
    if (current && current !== libraryId) throw new StoreError('this server holds another library', 409);
    this.db.prepare("INSERT OR IGNORE INTO meta (key, value) VALUES ('libraryId', ?)").run(libraryId);
    return libraryId;
  }

  /**
   * Stores each row unless the server already has a newer or equal `updatedAt`.
   * @returns {{applied: number, kept: {table: string, id: string}[], cursor: number}}
   */
  push(rows) {
    if (!Array.isArray(rows)) throw new StoreError('rows must be an array');
    for (const row of rows) validate(row);
    let applied = 0;
    const kept = [];
    this.db.exec('BEGIN IMMEDIATE');
    try {
      let seq = this.cursor();
      for (const row of rows) {
        const existing = this.find.get(row.table, row.id);
        if (existing && existing.updatedAt >= row.updatedAt) {
          kept.push({ table: row.table, id: row.id });
          continue;
        }
        seq += 1;
        this.upsert.run(row.table, row.id, row.updatedAt, row.deletedAt ?? null, JSON.stringify(row.data), seq);
        applied += 1;
      }
      this.db.exec('COMMIT');
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
    return { applied, kept, cursor: this.cursor() };
  }

  /** Rows changed after `after`, oldest first, at most `limit`. */
  pull(after = 0, limit = 500) {
    const page = this.since.all(after, Math.min(Math.max(limit, 1), 5000) + 1);
    const more = page.length > limit;
    const rows = page.slice(0, limit).map((r) => ({
      table: r.tbl, id: r.id, updatedAt: r.updatedAt, deletedAt: r.deletedAt, data: JSON.parse(r.data), seq: Number(r.seq),
    }));
    return { rows, cursor: rows.length ? rows[rows.length - 1].seq : after, more };
  }

  /** The next number of each sequence. */
  numbers() {
    return Object.fromEntries(this.db.prepare('SELECT name, next FROM sequence').all().map((r) => [r.name, Number(r.next)]));
  }

  /** Hands out `count` numbers in a row from a sequence: the first one is returned. */
  take(name, count = 1) {
    if (!SEQUENCES.includes(name)) throw new StoreError(`no sequence named ${name}`, 404);
    if (!Number.isInteger(count) || count < 1 || count > 100) throw new StoreError('count must be 1 to 100');
    if (name !== 'ticket' && count !== 1) throw new StoreError('invoice and credit numbers are handed out one at a time');
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const first = Number(this.db.prepare('SELECT next FROM sequence WHERE name = ?').get(name).next);
      this.db.prepare('UPDATE sequence SET next = ? WHERE name = ?').run(first + count, name);
      this.db.exec('COMMIT');
      return { first, count };
    } catch (error) {
      this.db.exec('ROLLBACK');
      throw error;
    }
  }

  /** Moves a sequence forward so it starts at `atLeast` or later; never backward. */
  startAt(name, atLeast) {
    if (!SEQUENCES.includes(name)) throw new StoreError(`no sequence named ${name}`, 404);
    if (!Number.isInteger(atLeast) || atLeast < 1) throw new StoreError('atLeast must be a positive integer');
    this.db.prepare('UPDATE sequence SET next = MAX(next, ?) WHERE name = ?').run(atLeast, name);
    return this.numbers()[name];
  }

  /** Takes back a number that went unused, when nothing was handed out after it. */
  giveBack(name, number) {
    if (!SEQUENCES.includes(name)) throw new StoreError(`no sequence named ${name}`, 404);
    if (!Number.isInteger(number) || number < 1) throw new StoreError('number must be a positive integer');
    const changes = this.db.prepare('UPDATE sequence SET next = ? WHERE name = ? AND next = ?').run(number, name, number + 1).changes;
    return Number(changes) === 1;
  }

  fileRecord(id) {
    checkID(id);
    const r = this.db.prepare('SELECT id, sha256, size FROM file WHERE id = ?').get(id);
    return r ? { id: r.id, sha256: r.sha256, size: Number(r.size) } : null;
  }

  recordFile(id, sha256, size) {
    checkID(id);
    this.db.prepare(`INSERT INTO file (id, sha256, size, storedAt) VALUES (?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET sha256 = excluded.sha256, size = excluded.size, storedAt = excluded.storedAt`)
      .run(id, sha256, size, new Date().toISOString());
  }
}

export function checkID(id) {
  if (typeof id !== 'string' || !ID.test(id)) throw new StoreError('id is missing or malformed');
}

function validate(row) {
  if (!row || typeof row !== 'object') throw new StoreError('each row must be an object');
  if (typeof row.table !== 'string' || !TABLE.test(row.table)) throw new StoreError('row.table is missing or malformed');
  checkID(row.id);
  if (typeof row.updatedAt !== 'string' || row.updatedAt.length < 10) throw new StoreError(`row ${row.table}/${row.id} has no updatedAt`);
  if (row.deletedAt != null && typeof row.deletedAt !== 'string') throw new StoreError(`row ${row.table}/${row.id} has a malformed deletedAt`);
  if (!row.data || typeof row.data !== 'object' || Array.isArray(row.data)) throw new StoreError(`row ${row.table}/${row.id} has no data`);
}
