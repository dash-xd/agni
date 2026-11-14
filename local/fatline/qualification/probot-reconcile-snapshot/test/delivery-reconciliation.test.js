'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { reconcileDelivery } = require('../src/delivery-reconciliation');

function fixture() {
  const delivery = {
    deliveryId: 'delivery-123', providerDeliveryId: 'stream-123',
    executionStatus: 'ambiguous', reconciliationId: null,
  };
  const effects = new Map([['delivery-123', 'applied']]);
  const settlements = [];
  const store = {
    async getDelivery(id) { return id === delivery.deliveryId ? { ...delivery } : null; },
    async applyDeliveryReconciliation({ deliveryId, providerDeliveryId, decisionId, decision }) {
      if (deliveryId !== delivery.deliveryId || providerDeliveryId !== delivery.providerDeliveryId) return 'conflict';
      const target = decision === 'confirm_applied' ? 'succeeded' : 'failed';
      if (delivery.reconciliationId) {
        return delivery.reconciliationId === decisionId &&
          delivery.reconciliationDecision === decision &&
          delivery.executionStatus === target ? 'already_applied' : 'conflict';
      }
      if (delivery.executionStatus !== 'ambiguous') return 'conflict';
      delivery.reconciliationId = decisionId;
      delivery.reconciliationDecision = decision;
      delivery.executionStatus = target;
      return 'applied';
    },
    async recordDeliveryOutcome(_, { status }) { delivery.outcomeStatus = status; },
  };
  const skymill = {
    async ack(id) { settlements.push(['ack', id]); },
    async nack(id) { settlements.push(['nack', id]); },
  };
  const authorize = async ({ actor }) => actor === 'operator';
  const verifyEffect = async ({ delivery: item }) => ({
    deliveryId: item.deliveryId, state: effects.get(item.deliveryId) || 'unknown',
    evidenceRef: 'fixture:effect:delivery-123', source: 'mock-github',
  });
  const request = {
    store, skymill, authorize, verifyEffect,
    actor: 'operator', deliveryId: delivery.deliveryId,
    decisionId: 'decision-123', decision: 'confirm_applied',
  };
  return { delivery, effects, settlements, store, skymill, request };
}

test('verified applied effect transitions once and ACKs, replay resumes idempotently', async () => {
  const f = fixture();
  assert.deepEqual(await reconcileDelivery(f.request), {
    status: 'reconciled', decisionId: 'decision-123', settlement: 'acked',
  });
  assert.equal(f.delivery.executionStatus, 'succeeded');
  assert.equal(f.delivery.outcomeStatus, 'acked');
  assert.deepEqual(f.settlements, [['ack', 'stream-123']]);
  const repeated = await reconcileDelivery(f.request);
  assert.equal(repeated.status, 'reconciled');
  assert.equal(f.settlements.length, 1);
  assert.equal(f.delivery.reconciliationId, 'decision-123');
});

test('missing authorizer or verifier fails closed', async () => {
  const f = fixture();
  await assert.rejects(reconcileDelivery({ ...f.request, authorize: undefined }), /requires/);
  await assert.rejects(reconcileDelivery({ ...f.request, verifyEffect: undefined }), /requires/);
  assert.equal(f.delivery.executionStatus, 'ambiguous');
});

test('unauthorized actor cannot modify execution or settle delivery', async () => {
  const f = fixture();
  assert.deepEqual(await reconcileDelivery({ ...f.request, actor: 'guest' }), {
    status: 'blocked', reason: 'unauthorized',
  });
  assert.equal(f.delivery.executionStatus, 'ambiguous');
  assert.equal(f.settlements.length, 0);
});

test('unknown, conflicting, and mismatched proof never unlock the fence', async () => {
  const f = fixture();
  f.effects.set('delivery-123', 'unknown');
  assert.deepEqual(await reconcileDelivery(f.request), {
    status: 'blocked', reason: 'effect_unresolved',
  });
  const mismatched = await reconcileDelivery({ ...f.request, verifyEffect: async () => ({
    deliveryId: 'wrong', state: 'applied', evidenceRef: 'fixture:x', source: 'mock',
  }) });
  assert.deepEqual(mismatched, { status: 'blocked', reason: 'evidence_unverified' });
  f.effects.set('delivery-123', 'absent');
  assert.equal((await reconcileDelivery(f.request)).status, 'blocked');
  assert.equal(f.delivery.executionStatus, 'ambiguous');
  assert.deepEqual(f.settlements, []);
});

test('verified absent effect permits explicit retry but never ACK', async () => {
  const f = fixture();
  f.effects.set('delivery-123', 'absent');
  const result = await reconcileDelivery({ ...f.request, decision: 'retry_verified_absent' });
  assert.deepEqual(result, {
    status: 'retry_authorized', decisionId: 'decision-123', settlement: 'nacked',
  });
  assert.equal(f.delivery.executionStatus, 'failed');
  assert.deepEqual(f.settlements, [['nack', 'stream-123']]);
});

test('contradicting second decision cannot overwrite first fence resolution', async () => {
  const f = fixture();
  await reconcileDelivery(f.request);
  const result = await reconcileDelivery({ ...f.request, decisionId: 'other' });
  assert.deepEqual(result, { status: 'blocked', reason: 'execution_not_ambiguous' });
  assert.equal(f.delivery.reconciliationId, 'decision-123');
});

test('failed ACK leaves succeeded fence, same decision may resume settlement', async () => {
  const f = fixture();
  let failed = false;
  f.skymill.ack = async id => {
    if (!failed) { failed = true; throw new Error('temporary outage'); }
    f.settlements.push(['ack', id]);
  };
  assert.deepEqual(await reconcileDelivery(f.request), {
    status: 'ack_pending', decisionId: 'decision-123', settlement: 'unconfirmed',
  });
  assert.equal(f.delivery.executionStatus, 'succeeded');
  assert.equal(f.delivery.outcomeStatus, undefined);
  assert.equal((await reconcileDelivery(f.request)).status, 'reconciled');
  assert.deepEqual(f.settlements, [['ack', 'stream-123']]);
});

test('delivery identity and decision ids are required', async () => {
  const f = fixture();
  await assert.rejects(reconcileDelivery({ ...f.request, decisionId: '' }), /invalid/);
  await assert.rejects(reconcileDelivery({ ...f.request, deliveryId: 'other!' }), /invalid/);
  assert.deepEqual(await reconcileDelivery({ ...f.request, deliveryId: 'missing' }), {
    status: 'blocked', reason: 'unknown_delivery',
  });
});
