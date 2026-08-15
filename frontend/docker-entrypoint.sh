#!/bin/sh
# ---------------------------------------------------------------------------
# This entrypoint runs at container startup, BEFORE nginx starts, and
# regenerates /usr/share/nginx/html/assets/env.js from the API_URL
# environment variable.
#
# This is what makes the "runtime config" pattern actually work once the
# Angular app is packaged into a container image:
#   - The Angular app is compiled ONCE into static JS/HTML/CSS at build time.
#   - That compiled bundle reads window.__env.apiUrl at runtime (see
#     src/app/core/config.service.ts and src/assets/env.js).
#   - Instead of baking a backend URL into the compiled JS, we overwrite
#     assets/env.js right before nginx serves it, based on an env var
#     supplied to `docker run` / the Kubernetes Pod spec.
#
# Practical effect: the exact same built image can be deployed against
# dev, staging, or prod backends (or a different namespace's backend)
# just by changing the API_URL env var on the container/Pod - no rebuild
# of the Angular app required.
#
# In Kubernetes this file can also be bypassed entirely by mounting a
# ConfigMap directly at /usr/share/nginx/html/assets/env.js, in which case
# this script's `cat` below would just be overwritten again by nginx
# reading the mounted file - either mechanism achieves the same goal.
# ---------------------------------------------------------------------------
set -e

: "${API_URL:=/api}"

cat <<EOF > /usr/share/nginx/html/assets/env.js
window.__env = {
  apiUrl: "${API_URL}"
};
EOF

exec "$@"
