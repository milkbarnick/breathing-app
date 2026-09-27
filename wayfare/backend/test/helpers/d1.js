/**
 * A minimal in-memory stand-in for Cloudflare D1, backed by Node's built-in
 * node:sqlite, so the real SQL in src/ and migrations/ can be exercised in tests.
 * Implements prepare().bind().first()/all()/run() and batch() (transactional).
 */
import { readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const require = createRequire(import.meta.url);
const { DatabaseSync } = require('node:sqlite');

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '..', '..', 'migrations');

function check(args) {
  for (const a of args) {
    if (a === undefined) throw new Error('D1_TYPE_ERROR: Type undefined is not supported as a bind value');
    if (typeof a === 'boolean') throw new Error('D1 shim: bind booleans as 1/0');
  }
}

class Stmt {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }
  bind(...args) {
    check(args);
    return new Stmt(this.db, this.sql, args);
  }
  _prep() {
    return this.db.raw.prepare(this.sql);
  }
  async first(col) {
    const rows = this._prep().all(...this.args);
    const row = rows[0] ? { ...rows[0] } : null;
    if (col) return row ? row[col] : null;
    return row;
  }
  async all() {
    return { success: true, results: this._prep().all(...this.args).map((r) => ({ ...r })), meta: {} };
  }
  async run() {
    if (/\bRETURNING\b/i.test(this.sql) || /^\s*(SELECT|WITH)\b/i.test(this.sql)) {
      const results = this._prep().all(...this.args).map((r) => ({ ...r }));
      return { success: true, results, meta: { changes: results.length } };
    }
    const r = this._prep().run(...this.args);
    return { success: true, results: [], meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
  }
}

export class FakeD1 {
  constructor() {
    this.raw = new DatabaseSync(':memory:');
    this.raw.exec('PRAGMA foreign_keys = ON;'); // D1 enforces foreign keys by default
    for (const f of readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort()) {
      this.raw.exec(readFileSync(join(migrationsDir, f), 'utf8'));
    }
  }
  prepare(sql) {
    return new Stmt(this, sql);
  }
  async batch(stmts) {
    this.raw.exec('BEGIN');
    try {
      const out = [];
      for (const s of stmts) out.push(await s.run());
      this.raw.exec('COMMIT');
      return out;
    } catch (err) {
      this.raw.exec('ROLLBACK');
      throw err;
    }
  }
  async exec(sql) {
    this.raw.exec(sql);
  }
}
