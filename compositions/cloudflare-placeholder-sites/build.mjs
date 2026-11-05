import { readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { loadManifest } from './validate.mjs'

const manifestPath = process.argv[2]
const outputPath = process.argv[3]
if (!manifestPath || !outputPath) throw new Error('Usage: node build.mjs <manifest.json> <output.mjs>')
const manifest = loadManifest(manifestPath)
const source = readFileSync(new URL('./worker.mjs', import.meta.url), 'utf8')
const output = source + '\nconst handler = createHandler(' + JSON.stringify(manifest) + ')\nexport default { fetch: handler }\n'
mkdirSync(resolve(outputPath, '..'), { recursive: true })
writeFileSync(outputPath, output, { flag: 'w' })
