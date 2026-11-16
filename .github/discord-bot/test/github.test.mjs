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
});
