import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

export function validateManifest(manifest) {
  if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest) || manifest.schema !== 1 ||
      !Array.isArray(manifest.hosts) || manifest.hosts.length === 0 ||
      typeof manifest.service !== 'string' || !/^[a-z][a-z0-9-]{0,61}[a-z0-9]$/.test(manifest.service)) {
    throw new TypeError('Invalid manifest envelope')
  }
  const names = new Set()
  for (const site of manifest.hosts) {
    if (!site || typeof site !== 'object' || Array.isArray(site) ||
        typeof site.hostname !== 'string' || typeof site.zone !== 'string' || typeof site.title !== 'string' ||
        !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(site.hostname) ||
        !/^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?$/.test(site.zone) ||
        site.hostname !== site.zone && !site.hostname.endsWith('.' + site.zone) ||
        !site.title.trim() || names.has(site.hostname)) {
      throw new TypeError('Invalid hostname, zone, or duplicate manifest entry')
    }
    names.add(site.hostname)
  }
  return manifest
}

export function loadManifest(path) {
  return validateManifest(JSON.parse(readFileSync(path, 'utf8')))
}

if (process.argv[1] && fileURLToPath(import.meta.url) === fileURLToPath(new URL('file://' + process.argv[1]))) {
  const manifest = loadManifest(process.argv[2] ?? new URL('./hosts.json', import.meta.url))
  process.stdout.write(JSON.stringify({ service: manifest.service, hosts: manifest.hosts.length }) + '\n')
}
