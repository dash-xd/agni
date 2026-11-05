// Pure handler: no Cloudflare API, bindings, or external dependencies.
export function createHandler(manifest) {
  if (manifest?.schema !== 1 || !Array.isArray(manifest.hosts)) throw new TypeError('Invalid manifest')
  const sites = new Map()
  for (const site of manifest.hosts) {
    if (!site.hostname || !site.title || sites.has(site.hostname)) throw new TypeError('Invalid or duplicate hostname')
    sites.set(site.hostname, site)
  }
  return function fetch(request) {
    const url = new URL(request.url)
    const site = sites.get(url.hostname)
    if (!site || (request.method !== 'GET' && request.method !== 'HEAD') || url.pathname !== '/') {
      return new Response('Not Found', { status: 404 })
    }
    const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))
    const html = '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>' +
      escape(site.title) + '</title><main><h1>' + escape(site.hostname) + '</h1><p>Coming soon.</p></main></html>'
    return new Response(request.method === 'HEAD' ? null : html, {
      status: 200,
      headers: {'content-type':'text/html; charset=utf-8','cache-control':'public, max-age=300',
        'x-content-type-options':'nosniff','x-robots-tag':'noindex'}
    })
  }
}
