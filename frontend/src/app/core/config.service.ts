import { Injectable } from '@angular/core';

// Shape of the window.__env object set by assets/env.js (and regenerated
// at container startup by docker-entrypoint.sh from the API_URL env var).
interface RuntimeEnv {
  apiUrl?: string;
}

declare global {
  interface Window {
    __env?: RuntimeEnv;
  }
}

/**
 * Reads backend configuration at RUNTIME rather than at Angular build time.
 *
 * Why: a normal Angular `environment.ts` file gets inlined into the compiled
 * JS bundle at `ng build` time, meaning a single build can only ever point at
 * one backend URL. In a containerized, multi-environment DevOps workflow
 * (dev/staging/prod, or multiple Kubernetes namespaces) we want to build the
 * Docker image ONCE and deploy that exact same image everywhere, just
 * pointing it at a different backend per environment.
 *
 * To achieve that, the backend URL is not compiled into main.js at all.
 * Instead:
 *   1. `src/assets/env.js` is a plain (non-TypeScript, non-bundled) script
 *      that sets `window.__env = { apiUrl: '...' }`.
 *   2. `index.html` loads that script via a <script> tag BEFORE main.js.
 *   3. This service simply reads `window.__env.apiUrl` at runtime.
 *   4. In Docker, `docker-entrypoint.sh` rewrites assets/env.js from the
 *      `API_URL` environment variable before nginx starts serving files -
 *      or, in Kubernetes, a ConfigMap can be mounted directly over
 *      assets/env.js. Either way, no Angular rebuild is required to
 *      repoint the app at a different backend.
 */
@Injectable({ providedIn: 'root' })
export class ConfigService {
  get apiUrl(): string {
    // Fallback to '/api' for safety in case window.__env / env.js failed to
    // load for some reason (e.g. a misconfigured static file server).
    return window.__env?.apiUrl ?? '/api';
  }
}
