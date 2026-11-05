import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { test } from 'node:test'
import { createHandler } from './worker.mjs'
const manifest = JSON.parse(readFileSync(new URL('./hosts.json', import.meta.url), 'utf8'))
const fetch = createHandler(manifest)
test('each exact hostname serves its own placeholder', async () => {
  assert.equal(manifest.hosts.length, 2)
  for (const site of manifest.hosts) {
    const response = fetch(new Request('https://' + site.hostname + '/'))
    assert.equal(response.status, 200)
    assert.match(await response.text(), new RegExp(site.hostname.replaceAll('.', '\\.')))
    assert.equal(response.headers.get('x-robots-tag'), 'noindex')
    const head = fetch(new Request('https://' + site.hostname + '/', {method:'HEAD'}))
    assert.equal(head.status, 200)
    assert.equal(await head.text(), '')
  }
})
test('unknown hosts and paths fail closed', () => {
  for (const url of ['https://unknown.example/','https://example.com/admin','https://evil.example.com/']) {
    assert.equal(fetch(new Request(url)).status, 404)
  }
})
test('duplicate hostnames are rejected', () => {
  assert.throws(() => createHandler({schema:1,hosts:[manifest.hosts[0],manifest.hosts[0]]}))
})
