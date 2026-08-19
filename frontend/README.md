# ecommerce-web (frontend)

Angular 17 standalone-components single-page app for the ecommerce DevOps teaching lab.

## Local development

```
npm install
npm start
```

This runs `ng serve` against `http://localhost:4200`. In dev mode, `src/assets/env.js` sets
`window.__env.apiUrl = '/api'`; use a dev proxy or run the backend so that path resolves, or
edit `src/assets/env.js` locally to point at `http://localhost:<backend-port>/api`.

## Production build

```
npm run build
```

Output is emitted to `dist/ecommerce-web/browser` (Angular 17's `application` builder nests
build output under a `browser/` subfolder).

## Docker / runtime configuration

The `Dockerfile` builds the app once (`npm ci` + `ng build --configuration production`) and
copies the compiled static files into an `nginx:1.27-alpine` image. `nginx.conf` serves the SPA
with a client-side routing fallback and proxies `/api/` to the `ecommerce-api` Kubernetes Service.

Because the Angular bundle is compiled once but may need to point at different backend URLs in
different environments, the backend URL is **not** baked into the JS bundle. Instead,
`docker-entrypoint.sh` runs before nginx starts and regenerates `assets/env.js` from the
`API_URL` environment variable given to the container (defaulting to `/api`). The compiled app
reads `window.__env.apiUrl` at runtime via `ConfigService`. This means the same built image can
be redeployed against a different backend just by changing an env var (or by mounting a
Kubernetes ConfigMap over `assets/env.js`) — no rebuild required.
