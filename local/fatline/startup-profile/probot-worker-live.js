#!/usr/bin/env node
'use strict';
// Transient isolated live-backed VM1 candidate. Never bind the production namespace.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawn } = require('node:child_process');
const { setTimeout: delay } = require('node:timers/promises');

async function main() {
  const [redisBin, skymillBin, nodeBin, probotRoot] = process.argv.slice(2);
  assert.match(redisBin || '', /^\/nix\/store\/[a-z0-9]{32}-[^/]+\/bin\/redis-server$/);
  assert.match(skymillBin || '', /^\/nix\/store\/[a-z0-9]{32}-skymill-http$/);
  assert.match(nodeBin || '', /^\/nix\/store\/[a-z0-9]{32}-[^/]+\/bin\/node$/);
  assert.match(probotRoot || '', /^\/nix\/store\/[a-z0-9]{32}-probot$/);
  const { RedisStore } = require(path.join(probotRoot, 'src/store'));
  const { normalizeBinding, bindingDigest, bindingArtifactKey } = require(path.join(probotRoot, 'src/authority'));
  const workspace = fs.mkdtempSync('/tmp/agni-worker-live-');
  fs.chmodSync(workspace, 0o700);
  const scope = 'worker-candidate';
  const statePrefix = 'xd-dash:fatline:runtime:probot-runtime:' + scope;
  const consumerGroup = 'agni-worker-candidate';
  const skymillToken = crypto.randomBytes(32).toString('hex');
  const redisSkymill = crypto.randomBytes(32).toString('hex');
  const redisState = crypto.randomBytes(32).toString('hex');
  const operatorToken = crypto.randomBytes(32).toString('hex');
  const secret = crypto.randomBytes(32).toString('hex');
  const routingKey = 'agni-worker-live';
  const appId = 900000077;
  const installationId = 900000078;
  const guid = crypto.randomUUID();
  const children = new Map();
  const baseEnv = { HOME: workspace, TMPDIR: workspace, PATH: '/bin:/usr/bin',
    NODE_ENV: 'test', NO_COLOR: '1' };
  const acl = [
    'user default off',
    'user skymill on >' + redisSkymill + ' ~skymill:* +@all -@admin -@dangerous +eval',
    'user probot_state on >' + redisState + ' ~' + statePrefix + ':* ~xd-dash:fatline:auth:binding-artifact:* +@all -@admin -@dangerous +eval',
  ].join('\n') + '\n';
  function credential(name, value) {
    const file = path.join(workspace, name);
    fs.writeFileSync(file, value, { mode: 0o600, flag: 'wx' });
    return file;
  }
  const aclFile = credential('users.acl', acl.trimEnd());
  const skymillFile = credential('skymill-token', skymillToken);
  const stateFile = credential('state', redisState);
  const operatorFile = credential('operator', operatorToken);
  const keyPair = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const privateKey = keyPair.privateKey.export({ format: 'pem', type: 'pkcs8' });
  const redisUrl = 'redis://127.0.0.1:6379/0';

  function launch(name, bin, argv, env) {
    assert.ok(!children.has(name), 'candidate process already exists: ' + name);
    const child = spawn(bin, argv, {
      env: { ...baseEnv, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    children.set(name, child);
    for (const stream of [child.stdout, child.stderr]) {
      stream.on('data', chunk => {
        const output = String(chunk).trim();
        if (output && /error|failed|panic|fatal|unavailable/i.test(output)) {
          console.error('AGNI_WORKER_LIVE_PROCESS=' + name + ' event=application-error');
        }
      });
    }
    return child;
  }
  async function stop(name, signal = 'SIGTERM') {
    const child = children.get(name);
    if (!child) return;
    children.delete(name);
    if (child.exitCode !== null || child.signalCode) return;
    const ended = new Promise(resolve => child.once('exit', resolve));
    child.kill(signal);
    await Promise.race([ended, delay(3000).then(() => {
      if (child.exitCode === null && !child.signalCode) child.kill('SIGKILL');
    })]);
  }
  async function until(label, check, maxMs = 20000) {
    const deadline = Date.now() + maxMs;
    let last;
    while (Date.now() < deadline) {
      try {
        if (await check()) return;
      } catch (error) { last = error; }
      await delay(150);
    }
    throw new Error(label + ' unavailable' + (last ? ': ' + String(last.message) : ''));
  }
  function redisStore() {
    return new RedisStore({ url: redisUrl, username: 'probot_state', password: redisState,
      db: 0, prefix: statePrefix });
  }
  function startSkymill() {
    return launch('skymill', skymillBin, [], {
      REDIS_ADDR: '127.0.0.1:6379', REDIS_USERNAME: 'skymill', REDIS_PASSWORD: redisSkymill,
      REDIS_DB: '0', SKYMILL_ADDR: '127.0.0.1:8081',
      SKYMILL_ORG: 'xd-dash', SKYMILL_TENANT: scope,
      SKYMILL_APPLICATION: 'github-webhooks', SKYMILL_STREAM: 'worker-candidate.webhooks',
      SKYMILL_CONSUMER_GROUP: consumerGroup,
      SKYMILL_HTTP_TOKEN_FILE: skymillFile,
    });
  }
  function startProbot() {
    return launch('probot', nodeBin, [path.join(probotRoot, 'router/serve.js')], {
      HOST: '127.0.0.1', PORT: '3000', REDIS_URL: redisUrl, REDIS_DB: '0',
      REDIS_USERNAME: 'probot_state', REDIS_PASSWORD_FILE: stateFile,
      REDIS_PREFIX: statePrefix, PROBOT_RUNTIME_ORG_ID: 'xd-dash',
      PROBOT_RUNTIME_TENANT_ID: scope, PROBOT_RUNTIME_GITHUB_ORG: 'xd-dash',
      PROBOT_RUNTIME_PUBLIC_URL: 'http://127.0.0.1:3000',
      PROBOT_RUNTIME_OPERATOR_TOKEN_FILE: operatorFile, PROBOT_RUNTIME_RECONCILE_EVERY: '0',
      PROBOT_RUNTIME_WORKER_ENABLED: 'true', PROBOT_RUNTIME_WORKER_BATCH_LIMIT: '1',
      PROBOT_RUNTIME_WORKER_INTERVAL_MS: '150',
      SKYMILL_URL: 'http://127.0.0.1:8081', SKYMILL_TOKEN: skymillToken,
      SKYMILL_STREAM: 'worker-candidate.webhooks', SKYMILL_CONSUMER_GROUP: consumerGroup,
      LOGMA_ENABLED: 'false',
    });
  }
  async function status() {
    const response = await fetch('http://127.0.0.1:8081/v1/status', {
      headers: { authorization: 'Bearer ' + skymillToken }, signal: AbortSignal.timeout(1000),
    });
    if (!response.ok) throw new Error('Skymill HTTP not ready');
    return response.json();
  }
  async function post(signature) {
    const body = Buffer.from(JSON.stringify({
      ref: 'refs/heads/fixture', installation: { id: installationId },
      repository: { full_name: 'xd-dash/worker-qualification' },
    }));
    const response = await fetch('http://127.0.0.1:3000/probot/apps/' + routingKey + '/deliveries', {
      method: 'POST', body, signal: AbortSignal.timeout(5000),
      headers: {
        'content-type': 'application/json', 'x-github-event': 'push',
        'x-github-delivery': guid, 'x-hub-signature-256': signature,
      },
    });
    return { status: response.status, body: await response.text() };
  }
  const body = Buffer.from(JSON.stringify({
    ref: 'refs/heads/fixture', installation: { id: installationId },
    repository: { full_name: 'xd-dash/worker-qualification' },
  }));
  const signature = 'sha256=' + crypto.createHmac('sha256', secret).update(body).digest('hex');

  try {
    const redis = launch('redis', redisBin, [
      '--bind', '127.0.0.1', '--port', '6379', '--protected-mode', 'yes',
      '--save', '', '--appendonly', 'no', '--databases', '1', '--maxmemory', '40mb',
      '--maxmemory-policy', 'noeviction', '--aclfile', aclFile,
    ], {});
    await until('isolated Redis', async () => {
      assert.equal(redis.exitCode, null);
      const store = redisStore();
      try { await store.connect(); return true; } finally { await store.close().catch(() => {}); }
    });

    const store = redisStore();
    await store.connect();
    const binding = normalizeBinding({
      org_id: 'xd-dash', tenant_id: scope, auth_profile: 'minimal-v1',
      auth_policy_digest: 'sha256:' + 'a'.repeat(64), revision: 1,
    });
    const digest = bindingDigest(binding);
    const artifactKey = bindingArtifactKey(binding);
    await store.client.set(artifactKey, JSON.stringify(binding), { NX: true });
    await store.importCreated({
      routingKey, targetOrg: 'xd-dash',
      created: {
        appId, slug: 'agni-worker-live', clientId: 'fixture-client',
        clientSecret: 'fixture-only', privateKey, webhookSecret: secret,
        permissions: {}, events: ['push'], owner: { login: 'xd-dash' },
      },
      bindingDigest: digest, bindingArtifactKey: artifactKey, binding,
    });
    await store.putInstallation(appId, {
      id: installationId, account: { id: 900000079, login: 'xd-dash' },
      permissions: {}, events: ['push'], target_type: 'Organization',
    });
    await store.activateBinding(routingKey, {
      appId, installationId, bindingDigest: digest, qualificationDigest: 'b'.repeat(64),
    });
    console.log('AGNI_WORKER_LIVE_REDIS=passed instance=isolated acl=separate credentials=ephemeral');

    startSkymill();
    await until('Skymill HTTP', async () => {
      // The consumer group may not exist before Probot's first receive.
      const response = await fetch('http://127.0.0.1:8081/v1/status', {
        signal: AbortSignal.timeout(1000),
      });
      return response.status === 401;
    });
    startProbot();
    await until('worker-enabled Probot HTTP', async () => {
      const response = await fetch('http://127.0.0.1:3000/', { signal: AbortSignal.timeout(1000) });
      return response.ok;
    });
    console.log('AGNI_WORKER_LIVE_STACK=passed redis=real skymill=real probot=real worker=enabled');

    const rejected = await post('sha256=' + '0'.repeat(64));
    assert.equal(rejected.status, 401);
    assert.equal(await store.getDelivery(guid), null);

    // Fault injection only affects the disposable Skymill process.
    await stop('skymill', 'SIGKILL');
    const unavailable = await post(signature);
    assert.ok([500, 502, 503].includes(unavailable.status));
    assert.equal(await store.getDelivery(guid), null);
    startSkymill();
    await until('Skymill recovery', status);
    const accepted = await post(signature);
    assert.equal(accepted.status, 202);
    const duplicate = await post(signature);
    assert.equal(duplicate.status, 200);
    console.log('AGNI_WORKER_LIVE_INGRESS=passed invalid=denied dependency_failure=denied signed=accepted duplicate=deduplicated');

    await until('worker execution and ACK', async () => {
      const delivery = await store.getDelivery(guid);
      return delivery && delivery.executionStatus === 'succeeded' &&
        delivery.outcomeStatus === 'acked' ? true : false;
    }, 30000);
    const delivery = await store.getDelivery(guid);
    assert.equal(delivery.executionStatus, 'succeeded');
    assert.equal(delivery.outcomeStatus, 'acked');
    const skymillStatus = await status();
    assert.equal(skymillStatus.Pending.Count, 0);
    console.log('AGNI_WORKER_LIVE_DELIVERY=passed durable_execution=succeeded skymill_ack=true pending=0');

    await stop('probot', 'SIGKILL');
    startProbot();
    await until('Probot restart', async () => {
      const response = await fetch('http://127.0.0.1:3000/', { signal: AbortSignal.timeout(1000) });
      return response.ok;
    });
    const replay = await post(signature);
    assert.equal(replay.status, 200);
    assert.equal((await store.getDelivery(guid)).executionStatus, 'succeeded');
    assert.equal((await status()).Pending.Count, 0);
    console.log('AGNI_WORKER_LIVE_RECOVERY=passed skymill_restarted=true worker_restarted=true replay_deduplicated=true');

    await store.close();
    console.log('AGNI_WORKER_LIVE_CANDIDATE=passed backing=real isolated=true promotion=blocked github=offline');
  } finally {
    for (const name of ['probot', 'skymill', 'redis']) await stop(name, 'SIGKILL');
    fs.rmSync(workspace, { recursive: true, force: true });
    assert.equal(children.size, 0);
    console.log('AGNI_WORKER_LIVE_CLEANUP=passed processes=stopped secrets=discarded state=removed');
  }
}
main().catch(error => {
  console.error('AGNI_WORKER_LIVE_CANDIDATE=failed reason=' + String(error.message || error));
  process.exitCode = 1;
});
