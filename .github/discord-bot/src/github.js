// GitHub access for the worker: a GitHub App (installed on the repos only),
// signed with Web Crypto so it runs on Cloudflare Workers and in Node alike.

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

export function githubClient(token, fetchImpl = fetch) {
  async function call(method, path, body) {
    const res = await fetchImpl(`${API}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'aes-discord-bot',
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) {
      const text = await res.text().catch(() => '');
      throw new Error(`GitHub ${method} ${path} -> ${res.status} ${text.slice(0, 300)}`);
    }
    return res.status === 204 ? null : res.json();
  }
  return {
    call,
    createIssue: (repo, issue) => call('POST', `/repos/${repo}/issues`, issue),
    getIssue: (repo, n) => call('GET', `/repos/${repo}/issues/${n}`),
    addLabels: (repo, n, labels) => call('POST', `/repos/${repo}/issues/${n}/labels`, { labels }),
    removeLabel: (repo, n, label) => call('DELETE', `/repos/${repo}/issues/${n}/labels/${encodeURIComponent(label)}`).catch(() => null),
    // Every issue (open or closed) carrying a label, following pages.
    async issuesWithLabel(repo, label) {
      const out = [];
      for (let page = 1; page < 20; page++) {
        const batch = await call('GET', `/repos/${repo}/issues?state=all&per_page=100&page=${page}&labels=${encodeURIComponent(label)}`);
        out.push(...batch.filter((i) => !i.pull_request));
        if (batch.length < 100) break;
      }
      return out;
    },
    // An issue already made from this Discord post, if any.
    async findByThread(repo, threadId) {
      const q = encodeURIComponent(`repo:${repo} "discord-thread: ${threadId}" in:body is:issue`);
      const r = await call('GET', `/search/issues?q=${q}&per_page=1`);
      return r.items && r.items[0] ? r.items[0] : null;
    },
  };
}

export async function installationToken({ appId, privateKey, repo }, fetchImpl = fetch) {
  const key = await importAppKey(privateKey);
  const jwt = await appJwt(appId, key);
  const app = githubClient(jwt, fetchImpl);
  const inst = await app.call('GET', `/repos/${repo}/installation`);
  const tok = await app.call('POST', `/app/installations/${inst.id}/access_tokens`, {});
  return tok.token;
}
