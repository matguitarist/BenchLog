import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Store } from '../src/store.js';

const row = (id, updatedAt, data = {}, table = 'customer') => ({ table, id, updatedAt, deletedAt: null, data: { name: id, ...data } });

test('the newer updatedAt wins; an older or equal one is kept out', () => {
  const store = new Store(':memory:');
  assert.equal(store.push([row('a', '2026-11-09 10:00:00.000', { phone: '1' })]).applied, 1);
  const older = store.push([row('a', '2026-11-09 09:00:00.000', { phone: 'old' })]);
  assert.deepEqual(older.kept, [{ table: 'customer', id: 'a' }]);
  assert.equal(store.push([row('a', '2026-11-09 10:00:00.000', { phone: 'echo' })]).applied, 0);
  store.push([row('a', '2026-11-09 11:00:00.000', { phone: 'new' })]);
  const pulled = store.pull(0).rows;
  assert.equal(pulled.length, 1);
  assert.equal(pulled[0].data.phone, 'new');
});

test('pull returns rows changed after the cursor, in order, in pages', () => {
  const store = new Store(':memory:');
  store.push([row('a', '2026-01-01 00:00:00.000'), row('b', '2026-01-01 00:00:00.000'), row('c', '2026-01-01 00:00:00.000')]);
  const first = store.pull(0, 2);
  assert.deepEqual(first.rows.map((r) => r.id), ['a', 'b']);
  assert.equal(first.more, true);
  const second = store.pull(first.cursor, 2);
  assert.deepEqual(second.rows.map((r) => r.id), ['c']);
  assert.equal(second.more, false);
  store.push([row('a', '2026-01-02 00:00:00.000')]);
  assert.deepEqual(store.pull(second.cursor).rows.map((r) => r.id), ['a']);
  assert.equal(store.pull(store.cursor()).rows.length, 0);
});

test('deletions travel as rows with deletedAt', () => {
  const store = new Store(':memory:');
  store.push([row('a', '2026-01-01 00:00:00.000')]);
  store.push([{ ...row('a', '2026-01-02 00:00:00.000'), deletedAt: '2026-01-02 00:00:00.000' }]);
  assert.equal(store.pull(0).rows[0].deletedAt, '2026-01-02 00:00:00.000');
});

test('a malformed row rejects the whole push', () => {
  const store = new Store(':memory:');
  assert.throws(() => store.push([row('a', '2026-01-01 00:00:00.000'), { table: 'x; DROP', id: 'b', updatedAt: '2026', data: {} }]));
  assert.equal(store.info().rows, 0);
});

test('numbers: blocks of tickets, invoices one at a time, start never moves back', () => {
  const store = new Store(':memory:');
  assert.equal(store.startAt('ticket', 42), 42);
  assert.equal(store.startAt('ticket', 10), 42);
  assert.deepEqual(store.take('ticket', 10), { first: 42, count: 10 });
  assert.deepEqual(store.take('ticket'), { first: 52, count: 1 });
  store.startAt('invoice', 7);
  assert.deepEqual(store.take('invoice'), { first: 7, count: 1 });
  assert.deepEqual(store.take('invoice'), { first: 8, count: 1 });
  assert.throws(() => store.take('invoice', 2));
  assert.throws(() => store.take('nope'));
  assert.deepEqual(store.numbers(), { ticket: 53, invoice: 9, credit: 1 });
});

test('an unused number goes back only while it is the last one handed out', () => {
  const store = new Store(':memory:');
  const { first } = store.take('invoice');
  assert.equal(store.giveBack('invoice', first), true);
  assert.deepEqual(store.take('invoice'), { first, count: 1 });
  store.take('invoice');
  assert.equal(store.giveBack('invoice', first), false);
});

test('a server belongs to the first library that claims it', () => {
  const store = new Store(':memory:');
  assert.equal(store.info().libraryId, null);
  store.claim('lib-1');
  store.claim('lib-1');
  assert.throws(() => store.claim('lib-2'), /another library/);
  assert.equal(store.info().libraryId, 'lib-1');
});
