// GitHub access for the worker: a GitHub App (installed on the repos only),
// signed with Web Crypto so it runs on Cloudflare Workers and in Node alike.

import { LABELS, parseMarker, snowflakeMs, statusOf } from './core.js';

const API = 'https://api.github.com';

const b64url = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
const b64urlStr = (s) => b64url(new TextEncoder().encode(s));

function pemToDer(pem) {
  const b64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function derLen(n) {
  if (n < 0x80) return [n];
  const bytes = [];
  while (n > 0) { bytes.unshift(n & 0xff); n >>= 8; }
  return [0x80 | bytes.length, ...bytes];
}

// GitHub hands out PKCS#1 keys ("BEGIN RSA PRIVATE KEY"); Web Crypto only takes
// PKCS#8, so wrap it rather than asking anyone to run openssl.
export function pkcs1ToPkcs8(pkcs1) {
  const algId = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00];
  const octet = [0x04, ...derLen(pkcs1.length), ...pkcs1];
  const inner = [0x02, 0x01, 0x00, ...algId, ...octet];
  return new Uint8Array([0x30, ...derLen(inner.length), ...inner]);
}

export async function importAppKey(pem) {
  let der = pemToDer(pem);
  if (/BEGIN RSA PRIVATE KEY/.test(pem)) der = pkcs1ToPkcs8(der);
  return crypto.subtle.importKey('pkcs8', der, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
}

export async function appJwt(appId, key, now = Math.floor(Date.now() / 1000)) {
  const header = b64urlStr(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const payload = b64urlStr(JSON.stringify({ iat: now - 60, exp: now + 540, iss: String(appId) }));
  const sig = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(`${header}.${payload}`));
  return `${header}.${payload}.${b64url(sig)}`;
}

const MAX_PAGES = 100;
// How far before a post's creation its marker search starts: room for the
// clocks of Discord and GitHub to disagree.
const SINCE_MARGIN_MS = 60 * 60 * 1000;

export function githubClient(token, fetchImpl = fetch) {
  const headers = () => ({
    Authorization: `Bearer ${token}`,
    Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': 'discord-issue-bot',
    'Content-Type': 'application/json',
  });
  async function call(method, path, body) {
    const res = await fetchImpl(`${API}${path}`, {
      method,
      headers: headers(),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw Object.assign(new Error(`GitHub ${method} ${path} -> ${res.status} ${text.slice(0, 300)}`), { github: { method, path, status: res.status } });
    }
    // A 2xx was applied even when its body cannot be read.
    return res.status === 204 ? null : res.json().catch((e) => { throw Object.assign(e, { applied: true }); });
  }
  return {
    call,
    createIssue: (repo, issue) => call('POST', `/repos/${repo}/issues`, issue),
    getIssue: (repo, n) => call('GET', `/repos/${repo}/issues/${n}`),
    addLabels: (repo, n, labels) => call('POST', `/repos/${repo}/issues/${n}/labels`, { labels }),
    // A label already gone is fine; any other failure reaches the caller.
    removeLabel: (repo, n, label) => call('DELETE', `/repos/${repo}/issues/${n}/labels/${encodeURIComponent(label)}`)
      .catch((e) => { if (statusOf(e) === 404) return null; throw e; }),
    // Every issue (open or closed) carrying a label, following every page;
    // with `since` (epoch ms), only those last updated at or after it.
    async issuesWithLabel(repo, label, { since = null } = {}) {
      const after = since === null ? '' : `&since=${encodeURIComponent(new Date(since).toISOString())}`;
      const out = [];
      for (let page = 1; ; page++) {
        if (page > MAX_PAGES) throw new Error(`more than ${MAX_PAGES * 100} issues labeled ${label}; stopping rather than skipping some`);
        const batch = await call('GET', `/repos/${repo}/issues?state=all&per_page=100&page=${page}&labels=${encodeURIComponent(label)}${after}`);
        out.push(...batch.filter((i) => !i.pull_request));
        if (batch.length < 100) return out;
      }
    },
    // Every comment on an issue, following every page.
    async comments(repo, n) {
      const out = [];
      for (let page = 1; page <= MAX_PAGES; page++) {
        const batch = await call('GET', `/repos/${repo}/issues/${n}/comments?per_page=100&page=${page}`);
        out.push(...batch);
        if (batch.length < 100) return out;
      }
      throw new Error(`more than ${MAX_PAGES * 100} comments on ${repo} #${n}; stopping rather than skipping some`);
    },
    repoNodeId: async (repo) => (await call('GET', `/repos/${repo}`)).node_id,
    // Moves an issue to another repo of the same owner, making any label
    // the target lacks. An answer of `errors` throws GitHub's first message;
    // only FORBIDDEN with no issue moved, the answer a token without
    // Contents write gets, applied nothing and is marked `refused`.
    async transferIssue(issueId, repositoryId) {
      const out = await call('POST', '/graphql', {
        query: 'mutation($issueId: ID!, $repositoryId: ID!) { transferIssue(input: { issueId: $issueId, repositoryId: $repositoryId, createLabelsIfMissing: true }) { issue { number url } } }',
        variables: { issueId, repositoryId },
      });
      if (out.errors && out.errors.length) {
        const [first] = out.errors;
        throw Object.assign(new Error(first.message), { refused: first.type === 'FORBIDDEN' && !(out.data && out.data.transferIssue) });
      }
      const { number, url } = out.data.transferIssue.issue;
      return { number, url };
    },
    // An issue already made from this Discord post, if any. Reads the issue list
    // (consistent at once), not search (which lags); errors reach the caller.
    // An issue filed from a post was made, so last updated, after the post
    // was: only issues updated since then are read, so the search, which a
    // card press must finish in 1.5 s, does not grow with every issue ever
    // filed.
    async findByThread(repo, threadId) {
      const issues = await this.issuesWithLabel(repo, LABELS.fromDiscord, { since: snowflakeMs(threadId) - SINCE_MARGIN_MS });
      return issues.find((i) => {
        const m = parseMarker(i.body);
        return m && m.threadId === String(threadId);
      }) || null;
    },
    // A per-post lock: creating a label is atomic, so of two sends of the same
    // post at the same moment only one gets true. Released once the send ends.
    // Its description says when it was taken, which tells a lock left behind
    // from one a send, or a create GitHub may still apply, can hold.
    async claimThread(repo, threadId, at = Date.now()) {
      const taken = new Date(at).toISOString().slice(0, 19).replace('T', ' ');
      const res = await fetchImpl(`${API}/repos/${repo}/labels`, {
        method: 'POST', headers: headers(), body: JSON.stringify({ name: lockLabel(threadId), color: 'ededed', description: `Send to GitHub since ${taken} UTC` }),
      });
      if (res.ok) return true;
      const text = await res.text().catch(() => '');
      // Only "already exists" means another send holds the lock; any other
      // refusal (validation, abuse limits) is an error.
      if (res.status === 422 && /already_exists/.test(text)) return false;
      throw new Error(`GitHub POST /repos/${repo}/labels -> ${res.status} ${text.slice(0, 300)}`);
    },
    releaseThread: (repo, threadId) => call('DELETE', `/repos/${repo}/labels/${encodeURIComponent(lockLabel(threadId))}`),
  };
}

export const lockLabel = (threadId) => `discord-lock-${threadId}`;

// An installation token for `repo`, with the permissions GitHub granted it
// (null when its answer named none). Only a 404 on the installation read
// means the App is not installed there, so only that error says so. A
// caller checking several repos passes one signed `jwt` for all of them.
export async function installationAccess({ appId, privateKey, repo, jwt = null }, fetchImpl = fetch) {
  const app = githubClient(jwt || await appJwt(appId, await importAppKey(privateKey)), fetchImpl);
  const inst = await app.call('GET', `/repos/${repo}/installation`).catch((e) => {
    if (e.github && e.github.status === 404) e.notInstalled = true;
    throw e;
  });
  const tok = await app.call('POST', `/app/installations/${inst.id}/access_tokens`, {});
  return { token: tok.token, permissions: tok.permissions ?? null };
}

export async function installationToken(opts, fetchImpl = fetch) {
  return (await installationAccess(opts, fetchImpl)).token;
}
