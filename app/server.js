'use strict';

/**
 * eks-gitops-demo-app
 * Minimal Express microservice used as the demo workload for the
 * EKS GitOps Blueprint. Exposes liveness/readiness probes for
 * Kubernetes and a Prometheus-compatible /metrics endpoint.
 */

const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;
const APP_VERSION = process.env.APP_VERSION || '1.0.0';
const startTime = Date.now();

// Simple in-memory request counter for /metrics
let requestCount = 0;
app.use((req, res, next) => {
  requestCount += 1;
  next();
});

app.get('/', (req, res) => {
  res.json({
    service: 'eks-gitops-demo-app',
    version: APP_VERSION,
    message: 'Deployed with GitOps on Amazon EKS',
  });
});

/** Liveness probe: is the process alive? */
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

/**
 * Readiness probe: is the app ready to serve traffic?
 * Fails during the first few seconds after boot to demonstrate
 * graceful rollout behaviour.
 */
let ready = false;
setTimeout(() => {
  ready = true;
}, 5000);

app.get('/ready', (req, res) => {
  if (ready) {
    res.status(200).json({ status: 'ready' });
  } else {
    res.status(503).json({ status: 'starting' });
  }
});

/** Prometheus-style metrics (scrape-friendly, no client library needed). */
app.get('/metrics', (req, res) => {
  const uptimeSeconds = Math.floor((Date.now() - startTime) / 1000);
  res.type('text/plain').send(
    [
      '# HELP http_requests_total Total HTTP requests served',
      '# TYPE http_requests_total counter',
      `http_requests_total{app="eks-gitops-demo-app",version="${APP_VERSION}"} ${requestCount}`,
      '# HELP process_uptime_seconds Application uptime in seconds',
      '# TYPE process_uptime_seconds gauge',
      `process_uptime_seconds{app="eks-gitops-demo-app"} ${uptimeSeconds}`,
    ].join('\n') + '\n'
  );
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`eks-gitops-demo-app v${APP_VERSION} listening on port ${PORT}`);
});
