// A recording fake for fetch: routes are [method, RegExp on the URL, handler(body, url)].
export function fakeFetch(routes) {
  const calls = [];
  const fn = async (url, init = {}) => {
    const method = init.method || 'GET';
    const body = init.body ? JSON.parse(init.body) : undefined;
    calls.push({ method, url, body });
    const route = routes.find(([m, re]) => m === method && re.test(url));
    if (!route) return new Response(`no route for ${method} ${url}`, { status: 404 });
    const out = await route[2](body, url);
    if (out instanceof Response) return out;
    return new Response(out === null ? null : JSON.stringify(out ?? {}), { status: out === null ? 204 : 200 });
  };
  fn.calls = calls;
  fn.find = (method, re) => calls.filter((c) => c.method === method && re.test(c.url));
  return fn;
}

// A forum with the tags the real #aui-help has, plus the bot's status tags.
export const FORUM = {
  id: '900',
  available_tags: [
    { id: 't-retail', name: 'Retail' }, { id: 't-forever', name: 'Forever' },
    { id: 't-bug', name: 'Bug' }, { id: 't-feedback', name: 'Feedback/Request' },
    { id: 's-tri', name: 'Triaged' }, { id: 's-prog', name: 'In progress' },
    { id: 's-fix', name: 'Fixed, next update' }, { id: 's-ship', name: 'Shipped' },
    { id: 's-closed', name: 'Closed' },
  ],
};
