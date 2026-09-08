# k8s-lab — Setup Runbook

Rebuild the entire Kubernetes troubleshooting lab from scratch, in order.
Every step below already accounts for the real problems we hit building
this the first time — read the "why" notes so a future rebuild doesn't
silently reintroduce the same bugs.

Prerequisite: Docker Desktop must be running (`docker version` should
succeed) before step 1.

## 1. Create the kind cluster

```
kind create cluster --config "C:\ShubhamS\DevOps Demo\ecommerce-practice\k8s-lab\kind-config.yaml"
```

`kind-config.yaml` defines 3 nodes (1 control-plane + 2 workers) and maps
host ports **8085→80** and **8443→443** into the control-plane container
(not the default 80/443 — those are commonly blocked on Windows by a
Hyper-V port exclusion range; check with
`netsh interface ipv4 show excludedportrange protocol=tcp` if this ever
needs revisiting). It also stamps the label `ingress-ready=true` onto the
control-plane node specifically, via `kubeadmConfigPatches`.

Verify: `kubectl get nodes` — all 3 should show `Ready`.

## 2. Install metrics-server

```
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deployment metrics-server -n kube-system --type=json --patch-file="C:\ShubhamS\DevOps Demo\ecommerce-practice\k8s-lab\metrics-server-patch.json"
```

**Why the patch is required:** kind nodes use self-signed kubelet certs
that fail normal TLS hostname verification. The patch appends
`--kubelet-insecure-tls` to metrics-server's existing args (using a JSON
Patch `add` at `/args/-`, which appends to the list instead of replacing
it wholesale — replacing would have deleted the other required default
args). This is a `kind`-sandbox-only quirk; real clusters (AKS/EKS) don't
need this.

Verify: `kubectl get pods -n kube-system -l k8s-app=metrics-server` then
`kubectl top nodes` (may say "Metrics API not available" for the first
30-60s after the pod goes `Running` — needs one full scrape cycle first;
not a bug, just re-check after a minute).

## 3. Install ingress-nginx

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s
kubectl patch deployment ingress-nginx-controller -n ingress-nginx --type=merge --patch-file="C:\ShubhamS\DevOps Demo\ecommerce-practice\k8s-lab\ingress-nginx-node-patch.json"
```

**Why the third command is required — this is the bug we actually hit:**
despite this being the official "kind provider" manifest, the Deployment
it creates does **not** include `nodeSelector: {ingress-ready: "true"}` —
only `{"kubernetes.io/os":"linux"}`, which every node satisfies. Without
this patch, the controller pod can land on *any* node (we saw it land on
a worker), and since the port-forward from step 1 only exists on the
control-plane container, nothing would ever reach it — `curl` returns
`(52) Empty reply from server`. The patch forces it onto the
control-plane node specifically, where the port-forward actually is.

After this patch, the Deployment creates a **new** pod (pod template
changed) — wait for it, then confirm placement:
```
kubectl get pods -n ingress-nginx -o wide
```
`NODE` column must read `k8s-lab-control-plane`. If it doesn't yet,
give it a few seconds and re-check.

## 4. Deploy the checkout-api baseline app

```
kubectl apply -f "C:\ShubhamS\DevOps Demo\ecommerce-practice\k8s-lab\checkout-api-v1.yaml"
```

Creates the `ecom-prod` namespace, a ConfigMap, a Secret, a 5-replica
Deployment (`podinfo` image, readiness/liveness probes, resource
requests/limits), a Service, and an Ingress — the full realistic shape
we'll be intentionally breaking across every future incident.

## 5. Full verification

```
kubectl get pods -n ecom-prod
kubectl get endpoints checkout-api -n ecom-prod
curl http://localhost:8085/
```
All 5 pods `1/1 Running`, 5 real IPs in Endpoints, and the `curl` should
return a JSON response from podinfo. Only once all three of these pass is
the lab genuinely ready for an incident to be injected on top of it.
