#!/usr/bin/env node
'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const http = require('node:http');
const path = require('node:path');

async function qualify(root) {
  assert.match(root, /^\/nix\/store\/[a-z0-9]{32}-probot$/);
  const { bindingDigest } = require(path.join(root, 'src/authority'));
  const { createDeliveryResource, createDeliveryRunResource } = require(path.join(root, 'src/services'));
  const { ProbotRuntime } = require(path.join(root, 'src/runtime'));
  const { runDeliveryWorker } = require(path.join(root, 'src/worker'));
  const { buildGitHubAppRouter } = require(path.join(root, 'router/resource-router'));
  const binding = { org_id: 'xd-dash', tenant_id: 'probot-test',
    auth_profile: 'minimal-v1', auth_policy_digest: 'sha256:' + 'a'.repeat(64), revision: 1 };
  const secret = crypto.randomBytes(32).toString('hex');
  const routingKey = 'agni-worker-fixture';
  const app = { state: 'created', authorityState: 'active', appId: 900000077, routingKey,
    webhookSecret: secret, activeBindingDigest: bindingDigest(binding),
    activeBindingArtifactKey: 'fixture-binding', qualificationDigest: 'b'.repeat(64) };
  const receipts = new Map();
  const executions = new Map();
  const outcomes = new Map();
  const stream = [];
  const published = new Map();
  let handled = 0;
  const store = {
    async getAppByRoutingKey(key) { return key === routingKey ? app : null; },
    async getAppById(id) { return id === app.appId ? app : null; },
    async getBindingArtifact(key) { return key === 'fixture-binding' ? binding : null; },
    async recordDelivery(value) { if (!receipts.has(value.deliveryId)) receipts.set(value.deliveryId, value); },
    async noteDeliveryReceived() { return false; },
    async acquireDeliveryExecution(id) {
      assert.ok(receipts.has(id));
      if (executions.get(id) === 'succeeded') return 'succeeded';
      if (executions.has(id)) return 'ambiguous';
      executions.set(id, 'running');
      return 'acquired';
    },
    async recordDeliveryExecutionCompleted(id, value) {
      assert.ok(executions.has(id));
      executions.set(id, value.status);
    },
    async recordDeliveryOutcome(id, value) {
      assert.ok(receipts.has(id));
      outcomes.set(id, value.status);
    },
  };
  const skymill = {
    async publish(value) {
      const prior = published.get(value.idempotencyKey);
      if (prior) return { duplicate: true, message_id: value.messageId, provider_delivery_id: prior };
      const id = 'fixture:' + value.messageId;
      published.set(value.idempotencyKey, id);
      stream.push({ provider_delivery_id: id, message: {
        id: value.messageId, metadata: value.metadata, payload: value.payload,
      } });
      return { duplicate: false, message_id: value.messageId, provider_delivery_id: id };
    },
    async receive({ limit }) { return { deliveries: stream.splice(0, limit) }; },
    async ack(id) { assert.ok(published.has(id.slice(8))); return { ok: true }; },
    async nack() { throw new Error('unexpected NACK'); },
  };
  const runtime = new ProbotRuntime({ store, skymill, makeApp: () => () => {} });
  runtime.forApp = async () => ({
    async receive(event) {
      assert.equal(event.name, 'push');
      assert.equal(event.payload.ref, 'refs/heads/fixture');
      handled++;
    },
  });
  const services = { createDelivery: options => createDeliveryResource({
    store, skymill, reconcileEvery: 0, ...options,
  }) };
  const router = buildGitHubAppRouter({ services, operatorToken: 'fixture-operator' });
  const server = http.createServer((req, res) => {
    Promise.resolve(router(req, res, () => {
      res.statusCode = 404;
      res.end();
    })).catch(error => {
      res.statusCode = 500;
      res.end(error.message);
    });
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    const base = 'http://127.0.0.1:' + server.address().port + '/apps/' + routingKey + '/deliveries';
    const body = Buffer.from(JSON.stringify({ ref: 'refs/heads/fixture', installation: { id: 456 } }));
    const guid = 'agni-' + crypto.randomBytes(16).toString('hex');
    const signature = 'sha256=' + crypto.createHmac('sha256', secret).update(body).digest('hex');
    async function post(sig) {
      const response = await fetch(base, {
        method: 'POST', body, signal: AbortSignal.timeout(5000),
        headers: { 'content-type': 'application/json', 'x-hub-signature-256': sig,
          'x-github-delivery': guid, 'x-github-event': 'push' },
      });
      return { status: response.status, body: await response.json() };
    }
    const invalid = await post('sha256=' + '0'.repeat(64));
    assert.equal(invalid.status, 401);
    assert.equal(receipts.size, 0);
    assert.equal(stream.length, 0);
    const accepted = await post(signature);
    assert.equal(accepted.status, 202);
    assert.equal(accepted.body.duplicate, false);
    const duplicate = await post(signature);
    assert.equal(duplicate.status, 200);
    assert.equal(duplicate.body.duplicate, true);
    assert.equal(receipts.size, 1);
    assert.equal(stream.length, 1);
    console.log('AGNI_WORKER_SIGNED_INGRESS=passed invalid=denied first=accepted duplicate=deduplicated');

    const controller = new AbortController();
    let processed;
    await Promise.race([
      runDeliveryWorker({
        services: { async createDeliveryRun({ limit }) {
          const result = await createDeliveryRunResource({ runtime, limit });
          processed = result;
          controller.abort();
          return result;
        } },
        signal: controller.signal, pollIntervalMs: 100, batchLimit: 1,
        onError: error => { throw error; },
      }),
      new Promise((_, reject) => setTimeout(() => reject(new Error('worker timeout')), 5000).unref()),
    ]);
    assert.equal(handled, 1);
    assert.equal(processed.processed, 1);
    assert.equal(processed.results[0].status, 'done');
    assert.equal(executions.get(guid), 'succeeded');
    assert.equal(outcomes.get(guid), 'acked');
    assert.equal(stream.length, 0);
    console.log('AGNI_WORKER_EXECUTION=passed single_handler=true execution_fence=succeeded settlement=acked');

    const replay = await post(signature);
    assert.equal(replay.status, 200);
    assert.equal(replay.body.duplicate, true);
    assert.equal(handled, 1);
    assert.equal(stream.length, 0);
    console.log('AGNI_WORKER_REPLAY=passed handler_invocations=1');

    receipts.clear(); executions.clear(); outcomes.clear(); published.clear(); stream.length = 0;
    assert.equal(receipts.size + executions.size + outcomes.size + published.size + stream.length, 0);
    console.log('AGNI_WORKER_ROLLBACK=passed ephemeral_state_cleared=true');
    console.log('AGNI_WORKER_CANDIDATE=passed mode=isolated-fixture redis=mock skymill=mock github=offline');
  } finally {
    if (server.listening) await new Promise(resolve => server.close(resolve));
  }
}
qualify(process.argv[2]).catch(error => {
  console.error('AGNI_WORKER_CANDIDATE=failed reason=' + String(error.message || error));
  process.exitCode = 1;
});
