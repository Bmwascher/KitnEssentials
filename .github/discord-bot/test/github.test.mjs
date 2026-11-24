import test from 'node:test';
import assert from 'node:assert/strict';
import { githubClient } from '../src/github.js';
import { fakeFetch } from './fake-fetch.mjs';

test('a label list longer than 19 pages is read to the end', async () => {
  const page = (n) => Array.from({ length: 100 }, (_, i) => ({ number: n * 100 + i }));
  const f = fakeFetch([['GET', /\/issues\?/, (_, url) => {
    const n = Number(/[?&]page=(\d+)/.exec(url)[1]);
    return n <= 25 ? page(n) : [{ number: 99999 }];
  }]]);
  const all = await githubClient('t', f).issuesWithLabel('me/r', 'pending-release');
  assert.equal(all.length, 2501);
});

test('removing a label tolerates only "already gone"', async () => {
  const gone = fakeFetch([['DELETE', /labels/, () => new Response('nf', { status: 404 })]]);
  assert.equal(await githubClient('t', gone).removeLabel('me/r', 1, 'x'), null);
  const refused = fakeFetch([['DELETE', /labels/, () => new Response('no', { status: 403 })]]);
  await assert.rejects(githubClient('t', refused).removeLabel('me/r', 1, 'x'), /403/);
  const quoted = fakeFetch([['DELETE', /labels/, () => new Response('upstream said -> 404 x', { status: 500 })]]);
  await assert.rejects(githubClient('t', quoted).removeLabel('me/r', 1, 'x'), { message: /^GitHub DELETE \S+ -> 500 / });
});

test('the marker search reads only issues updated since shortly before the post was made', async () => {
  const made = Date.UTC(2026, 10, 18);
  const post = String(BigInt(made - 1420070400000) << 22n);
  const f = fakeFetch([['GET', /\/issues\?/, () => [{ number: 7, body: `<!-- discord-thread: ${post} reporter: 42 -->` }]]]);
  assert.equal((await githubClient('t', f).findByThread('me/r', post)).number, 7);
  const since = Date.parse(new URL(f.calls[0].url).searchParams.get('since'));
  // Before the post, so its own issue is never left out, and close to it, so
  // the list does not grow with every issue ever filed.
  assert.ok(since <= made && since > made - 24 * 60 * 60 * 1000, `since ${new Date(since).toISOString()}`);
});

test('a lock label says exactly when it was taken, by the clock the Worker uses', async () => {
  const real = Date.now;
  Date.now = () => Date.UTC(2026, 10, 18, 18, 40, 5);
  try {
    const f = fakeFetch([['POST', /\/labels$/, () => new Response('{}', { status: 201 })]]);
    // No time passed, as the Worker calls it.
    assert.equal(await githubClient('t', f).claimThread('me/r', '700'), true);
    assert.equal(f.calls[0].body.description, 'Send to GitHub since 2026-11-18 18:40:05 UTC');
  } finally { Date.now = real; }
});
