const MARKDOWN_ROUTES = new Map([
  ['/', '/index.md'],
  ['/index.html', '/index.md'],
  ['/contribute', '/contribute.md'],
  ['/contribute.html', '/contribute.md'],
  ['/showcase', '/showcase.md'],
  ['/showcase.html', '/showcase.md'],
]);

function parseAccept(header) {
  return header
    .split(',')
    .map((entry) => {
      const [type, ...params] = entry.trim().split(';');
      const qParam = params.find((param) => param.trim().startsWith('q='));
      const q = qParam ? Number.parseFloat(qParam.split('=')[1]) : 1;
      return { type: type.toLowerCase(), q: Number.isFinite(q) ? q : 0 };
    })
    .filter((entry) => entry.type);
}

function prefersMarkdown(request) {
  const accept = request.headers.get('Accept');
  if (!accept) return false;

  const entries = parseAccept(accept);
  const markdown = entries.find((entry) => entry.type === 'text/markdown');
  if (!markdown || markdown.q <= 0) return false;

  const html = entries.find((entry) => entry.type === 'text/html');
  return !html || markdown.q >= html.q;
}

function withVaryAccept(response) {
  const headers = new Headers(response.headers);
  const vary = headers.get('Vary');
  if (!vary) {
    headers.set('Vary', 'Accept');
  } else if (!vary.toLowerCase().split(',').map((value) => value.trim()).includes('accept')) {
    headers.set('Vary', `${vary}, Accept`);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

async function markdownResponse(request, env, pathname) {
  const markdownPath = MARKDOWN_ROUTES.get(pathname);
  if (!markdownPath) return null;

  const markdownUrl = new URL(markdownPath, request.url);
  const assetResponse = await env.ASSETS.fetch(new Request(markdownUrl, request));
  if (!assetResponse.ok) return null;

  const markdown = await assetResponse.text();
  const headers = new Headers(assetResponse.headers);
  headers.set('Content-Type', 'text/markdown; charset=utf-8');
  headers.set('Vary', 'Accept');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('x-markdown-tokens', String(markdown.trim().split(/\s+/).filter(Boolean).length));

  return new Response(markdown, {
    status: 200,
    headers,
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === 'GET' || request.method === 'HEAD') {
      if (prefersMarkdown(request)) {
        const markdown = await markdownResponse(request, env, url.pathname);
        if (markdown) {
          if (request.method === 'HEAD') {
            return new Response(null, {
              status: markdown.status,
              statusText: markdown.statusText,
              headers: markdown.headers,
            });
          }
          return markdown;
        }
      }
    }

    return withVaryAccept(await env.ASSETS.fetch(request));
  },
};
