'use strict';

// Application-owned recovery decision. No HTTP route exposes this operation.
// Authorization and effect verification are injected by the owning control plane.
const DECISIONS = new Set(['confirm_applied', 'retry_verified_absent']);

function validateDecision({ deliveryId, decisionId, decision }) {
  const token = value => typeof value === 'string' &&
    value.length >= 1 && value.length <= 128 &&
    /^[A-Za-z0-9][A-Za-z0-9._:-]*$/u.test(value);
  if (!token(deliveryId) || !token(decisionId) || !DECISIONS.has(decision)) {
    throw new Error('reconciliation identity or decision invalid');
  }
}

async function reconcileDelivery({
  store, skymill, authorize, verifyEffect,
  actor, deliveryId, decisionId, decision,
} = {}) {
  validateDecision({ deliveryId, decisionId, decision });
  if (!store || !skymill || typeof authorize !== 'function' ||
      typeof verifyEffect !== 'function') {
    throw new Error('reconciliation requires store, Skymill, authorizer and verifier');
  }

  const delivery = await store.getDelivery(deliveryId);
  if (!delivery || !delivery.providerDeliveryId) {
    return { status: 'blocked', reason: 'unknown_delivery' };
  }
  if (await authorize({ actor, delivery, decision, decisionId }) !== true) {
    return { status: 'blocked', reason: 'unauthorized' };
  }
  if (delivery.executionStatus !== 'ambiguous' &&
      delivery.reconciliationId !== decisionId) {
    return { status: 'blocked', reason: 'execution_not_ambiguous' };
  }

  // Only the trusted adapter supplies evidence; callers cannot assert success.
  const proof = await verifyEffect({
    delivery, decision, decisionId, idempotencyKey: deliveryId,
  });
  if (!proof || proof.deliveryId !== deliveryId ||
      typeof proof.evidenceRef !== 'string' || proof.evidenceRef.length === 0 ||
      proof.evidenceRef.length > 256 ||
      typeof proof.source !== 'string' || proof.source.length === 0 ||
      proof.source.length > 128) {
    return { status: 'blocked', reason: 'evidence_unverified' };
  }
  const requiredState = decision === 'confirm_applied' ? 'applied' : 'absent';
  if (proof.state !== requiredState) {
    return { status: 'blocked', reason: 'effect_unresolved' };
  }

  const transition = await store.applyDeliveryReconciliation({
    deliveryId, providerDeliveryId: delivery.providerDeliveryId,
    decisionId, decision, evidenceRef: proof.evidenceRef,
    evidenceSource: proof.source,
  });
  if (transition !== 'applied' && transition !== 'already_applied') {
    return { status: 'blocked', reason: 'decision_conflict' };
  }
  if (transition === 'already_applied' &&
      delivery.outcomeStatus === (decision === 'confirm_applied' ? 'acked' : 'nacked')) {
    return { status: decision === 'confirm_applied' ? 'reconciled' : 'retry_authorized',
      decisionId, settlement: delivery.outcomeStatus };
  }

  if (decision === 'retry_verified_absent') {
    // Do not ACK. Skymill retains ownership of delivery retries; an
    // unsuccessful NACK is not evidence of execution.
    try {
      await skymill.nack(delivery.providerDeliveryId);
    } catch {
      return { status: 'retry_pending', decisionId, settlement: 'unconfirmed' };
    }
    await store.recordDeliveryOutcome(deliveryId, {
      status: 'nacked', providerDeliveryId: delivery.providerDeliveryId,
    });
    return { status: 'retry_authorized', decisionId, settlement: 'nacked' };
  }

  // The execution fence is committed before transport settlement. If
  // settlement fails, retrying this same decision is safe and can resume ACK.
  try {
    await skymill.ack(delivery.providerDeliveryId);
  } catch {
    return { status: 'ack_pending', decisionId, settlement: 'unconfirmed' };
  }
  await store.recordDeliveryOutcome(deliveryId, {
    status: 'acked', providerDeliveryId: delivery.providerDeliveryId,
  });
  return { status: 'reconciled', decisionId, settlement: 'acked' };
}

module.exports = { reconcileDelivery };
