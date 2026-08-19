# Ecommerce AKS POC — Session Journal

A complete, chronological record of everything done in this hands-on Azure/AKS
learning session: what was built, every command run, every real error hit and
why, and the concepts behind each decision. Written for review, not for
replay — some values (image tags, IPs, resource names) will differ if you
redo any of this later, and any credential that appeared during the session
has been deliberately redacted here rather than copied forward.

**How to use this doc:** it's organized chronologically by module, in the
order things actually happened (including the dead ends). Each troubleshooting
section follows the same shape: the command that triggered it, the exact
error, the root cause, and the fix. Skip to whatever module you want to
review — each section is self-contained.

---

## 1. Session Context & Repo Overview

Goal: prepare for a Senior DevOps Engineer interview (Azure focus) using this
repo — a .NET 8 API + Angular 17 frontend + SQL Server app — as a hands-on
POC deployed for real against a live AKS cluster, rather than just discussing
concepts.

Repo layout at session start:
- `backend/` — .NET 8 Web API (Controllers, EF Core, ASP.NET Identity, JWT),
  multi-stage `dockerfile`, split health endpoints (`/health` = readiness incl.
  DB check, `/health/live` = liveness, process-only).
- `frontend/` — Angular 17 SPA, multi-stage `dockerfile` → `nginx-unprivileged`,
  runtime config injection via `docker-entrypoint.sh` regenerating
  `assets/env.js` from the `API_URL` env var.
- `docker-compose.yml` — SQL Server + API + Web, healthchecks, `.env`-based
  secrets.
- `k8s/base/` + `k8s/overlays/{dev,prod}` — Kustomize manifests (existed but
  unused at session start).
- `helm/ecommerce-chart/` — untouched `helm create` scaffold, not wired to
  the app.
- No Terraform, Azure DevOps pipelines, ArgoCD, or monitoring existed yet.

An AKS cluster (`pocdevcluster`, resource group `rg-poc`) was already created
before this session began.

---

## 2. Docker Fundamentals (brief)

Covered conceptually only (image vs. container vs. Docker Engine — recipe /
dish / kitchen analogy; image layers; why containers start faster than VMs)
before pivoting straight to hands-on cluster work given the time budget.

---

## 3. AKS Cluster Discovery

```bash
az account show -o table                     # confirm active subscription/tenant
az aks list -o table                          # found pocdevcluster in rg-poc, Sweden Central, K8s 1.35
az acr list -o table                          # found an unrelated ACR in a different RG — created a dedicated one instead
az aks show -g rg-poc -n pocdevcluster --query "{...}" -o json   # inspected network/identity config
az aks nodepool list -g rg-poc --cluster-name pocdevcluster      # returned [] — the key discovery below
```

The empty nodepool list revealed this is **AKS Automatic**
(`skuName: Automatic`, `nodeProvisioningMode: Auto`) — it uses **Node Auto
Provisioning** (Karpenter under the hood — later confirmed live via an event
source literally named `karpenter`) instead of classic, manually-sized node
pools.

**Concept — AKS Automatic vs. classic AKS:** Automatic gives secure-by-default
networking/identity/scaling with less manual control (no nodepool objects to
manage, opinionated policies baked in). Classic gives explicit
node-pool/taint/zone control, which is what most job-description language and
most existing companies still describe. Decision: keep AKS Automatic for this
POC; a classic cluster was later built purely via Terraform for comparison.

Also confirmed at this stage: `identityType: SystemAssigned`,
`loadBalancerSku: standard`, `networkPlugin: azure` +
`networkPluginMode: overlay` (Azure CNI Overlay), `networkPolicy: cilium`,
`oidcEnabled: true`, `workloadIdentityEnabled: true`, `privateCluster: false`.

---

## 4. ACR ↔ AKS Identity Wiring (AcrPull)

Goal: let AKS nodes pull images from a dedicated ACR (`acrecommercepoc`,
Basic SKU, admin disabled, created in `eastus`).

### Error: MSYS path mangling on Windows Git Bash

```
ERROR: (MissingSubscription) The request did not have a subscription or a
valid tenant level resource provider.
```

**Root cause:** Git Bash (MSYS2) auto-rewrites any `/subscriptions/...`-style
argument as if it were a Unix filesystem path, corrupting the real Azure
resource ID before `az` ever sees it.

**Fix:** prefix the command with `MSYS_NO_PATHCONV=1`, e.g.:
```bash
MSYS_NO_PATHCONV=1 az role assignment list --scope "$ACR_ID" -o table
```

### Error: AcrPull granted to the wrong identity

After granting `AcrPull` via the Azure Portal, verification showed it went to
the wrong identity entirely.

**Root cause:** an AKS cluster exposes **two separate identities** — the
control-plane `SystemAssigned` identity (manages Azure infra like load
balancers/disks around the cluster) and the **kubelet identity**
(`identityProfile.kubeletidentity.objectId`, used specifically by nodes to
pull images). The Portal's identity picker surfaced the wrong one.

**Fix:**
```bash
az ad sp show --id <kubeletIdentityObjectId> --query "{displayName,appId}"
# -> pocdevcluster-agentpool
```
Re-did the role assignment targeting **that** identity specifically. Verified:
```bash
az role assignment list --scope $ACR_ID --query "[].{principalId,role,type}"
```

**Cheat sheet:** control-plane identity manages Azure infra *around* the
cluster; kubelet identity is the only one that authenticates to ACR for image
pulls.

---

## 5. Docker Build & Push to ACR

```bash
docker info --format '{{.ServerVersion}}'          # confirm Docker daemon running
docker build -t acrecommercepoc.azurecr.io/ecommerce-api:1.0.0 -f backend/dockerfile backend
docker build -t acrecommercepoc.azurecr.io/ecommerce-web:1.0.0 ./frontend
docker images acrecommercepoc.azurecr.io/*
az acr login -n acrecommercepoc
docker push acrecommercepoc.azurecr.io/ecommerce-api:1.0.0
docker push acrecommercepoc.azurecr.io/ecommerce-web:1.0.0
az acr repository list -n acrecommercepoc -o table
az acr repository show-tags -n acrecommercepoc --repository ecommerce-api -o table
```

**Flagged risk (not fixed, just noted):** the frontend build ran without
`-f` and worked only because Windows filesystems are case-insensitive
(Dockerfiles in this repo are lowercase `dockerfile`) — this would silently
break on a Linux CI agent, a real "works on my machine, fails in the
pipeline" trap to revisit in the CI/CD module.

---

## 6. Connecting kubectl to AKS

```bash
az aks get-credentials -g rg-poc -n pocdevcluster --overwrite-existing
```
Uses the `kubelogin` plugin under the hood — Azure CLI authentication, no
static credential stored in kubeconfig.

### Error: Forbidden despite having Azure Contributor/Owner

```
Error from server (Forbidden): nodes is forbidden: User
"shubham.shinde@xperate.com" cannot list resource "nodes" ...
```

**Root cause:** this cluster uses **Azure RBAC for Kubernetes
Authorization** — a second, independent permission layer *inside* the
cluster, on top of normal ARM RBAC. Having enough ARM permissions to run
`get-credentials` grants zero actual `kubectl` permissions; that needs a
separate Azure role like `Azure Kubernetes Service RBAC Cluster Admin`.

**Fix:**
```bash
MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee <email> \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --scope $(az aks show -g rg-poc -n pocdevcluster --query id -o tsv)
```
After propagation: `kubectl get nodes -o wide` succeeded — 4 nodes, all
`Ready`, `containerd` runtime, split into `hostedpool` (workload) vs.
`system-surge` (core add-ons) node pools, OS = Microsoft Azure Linux 3.0.

---

## 7. Kustomize Manifest Fixes (pre-deploy)

- `k8s/base/kustomization.yaml` was including `secret.example.yaml` as a
  live resource, despite its own header saying "TEMPLATE ONLY, DO NOT
  APPLY." **Fix:** removed it from `resources:` (later replaced entirely by
  the Key Vault approach below).
- `k8s/overlays/prod/kustomization.yaml`'s `images:` transformer only
  overrode `newTag`, not `newName` — would still resolve to a placeholder
  `youracr.azurecr.io`. **Fix:** added `newName:` pointing at the real ACR
  for both `ecommerce-api` and `ecommerce-web`.

---

## 8. Key Vault + Workload Identity Federation

Chose to wire secrets through Key Vault + Workload Identity rather than
plain `kubectl create secret`.

```bash
az keyvault create -g rg-poc -n kv-ecommercepoc --location swedencentral --enable-rbac-authorization true
```

### Error: Vault name already taken

`(VaultAlreadyExists)` — confirmed via `az keyvault list-deleted` that it
wasn't even our own soft-deleted leftover; the name was globally taken by
someone else. **Fix:** recreated as `kv-ecommercepoc-xp`.

Granted self `Key Vault Secrets Officer` (RBAC-mode vaults start with **zero**
default access, even for the creator).

```bash
az keyvault secret set --vault-name kv-ecommercepoc-xp --name sa-password --value '...'
az keyvault secret set --vault-name kv-ecommercepoc-xp --name jwt-key --value '...'
az keyvault secret set --vault-name kv-ecommercepoc-xp --name connection-string --value '...'
```

### Error: cmd.exe swallows single quotes

`unrecognized arguments: Id=sa;Password=...` on the `connection-string`
value (which contains spaces).

**Root cause:** these were run in **cmd.exe**, not Bash/PowerShell, using
single quotes — cmd.exe doesn't treat `'...'` as a quoting character at
all, so the value split into stray arguments on every space. Worse: the two
earlier secrets (no spaces) didn't error but silently stored the **literal
quote characters** as part of the value.

**Fix:** re-ran all three commands with double quotes (which cmd.exe does
strip), retyping the two that had already gone stale (not recalled from
shell history, since history would just replay the broken version).

Continued:
```bash
az identity create -g rg-poc -n id-ecommerce-api --location swedencentral
# granted this identity's principalId "Key Vault Secrets User" (read-only) on the vault
az aks show -g rg-poc -n pocdevcluster --query "oidcIssuerProfile.issuerUrl" -o tsv
# created a federated credential on the identity via Portal: issuer = that URL,
# namespace ecommerce, service account ecommerce-workload-sa, audience api://AzureADTokenExchange
az identity federated-credential list --identity-name id-ecommerce-api -g rg-poc   # verify
```

**Self-corrected mid-flow:** first Portal attempt granted the app identity
`Key Vault Secrets Officer` (read/write/delete) instead of `Secrets User` —
over-privileged. Removed and re-granted the narrower role.

**Files created:**
- `k8s/base/serviceaccount.yaml` — ServiceAccount `ecommerce-workload-sa`
  with label `azure.workload.identity/use: "true"` (activates AKS's mutating
  webhook) and annotation `azure.workload.identity/client-id: <UAMI clientId>`.
- `k8s/base/secretproviderclass.yaml` — `SecretProviderClass` pointing at
  `kv-ecommercepoc-xp`, listing which secrets to fetch, and syncing them into
  native K8s Secrets (`ecommerce-db-secret`, `ecommerce-api-secret`) that the
  existing manifests already referenced via `secretKeyRef` — no app-side
  wiring changed.

**Wiring:** added `serviceAccountName: ecommerce-workload-sa` plus a CSI
`volumes`/`volumeMounts` pair (`/mnt/secrets-store`) to
`api-deployment.yaml` and `sql-statefulset.yaml` — the mount itself is what
triggers the CSI driver to actually fetch anything.

**Concept (badge/security-office analogy):** a federated credential is a
note telling Azure AD's security office "trust a badge from this exact
cluster claiming to be this exact ServiceAccount, and swap it for our real
badge (the managed identity)." The ServiceAccount is the pod's badge (label =
eligible for swap, annotation = swap into this identity). The
SecretProviderClass is an instruction sheet for what to fetch once inside,
and where to leave copies.

---

## 9. First Deployment Attempt (Kustomize)

```bash
kubectl kustomize k8s/overlays/prod                          # local render check
kubectl apply -f k8s/base/namespace.yaml                     # create namespace for real first
kubectl apply -k k8s/overlays/prod --dry-run=server           # then dry-run everything else
```

**Note on dry-run ordering:** running `--dry-run=server` on everything
*including* the namespace fails with `namespaces "ecommerce" not found` on
every object, because a dry-run namespace creation doesn't leave a real
namespace behind for the other objects' validation to see. Solved by
applying the namespace for real first (safe, non-destructive), then
dry-running the rest.

### Error: `latest` tag rejected by policy

```
admission webhook "validation.gatekeeper.sh" denied the request:
Avoiding the latest tag for container: web ... Consider using explicit versions
```

**Root cause:** `k8s/base/web-deployment.yaml` actually referenced
`shubhamxperate/ecommerce-web:latest` — a Docker Hub leftover from repo
scaffolding, completely different from the placeholder string the overlay's
`images:` transformer was trying to match. Kustomize's image transformer only
rewrites an *exact* match on `name:` and **silently does nothing** if it
matches zero images — so this sailed through untouched.

**Wrong fix attempted:** editing the container's `image:`/`name:` fields
directly to use `newName`/`newTag` — invalid, those are Kustomize-only
fields, not real Kubernetes API fields (`strict decoding error: unknown
field`).

**Correct fix:** reverted the base file to its original
`image: shubhamxperate/ecommerce-web:latest`; fixed the overlay's `images:`
block to match `name: shubhamxperate/ecommerce-web` (the string actually
present) with the real `newName`/`newTag`.

```bash
kubectl apply -k k8s/overlays/prod   # succeeded
```
AKS Automatic's mutating webhook auto-injected pod anti-affinity + topology
spread constraints on the resulting Deployments without being asked.

**Aside on Kustomize vs. Helm co-management:** the two tools stamp different
ownership annotations on live objects
(`kubectl.kubernetes.io/last-applied-configuration` vs. Helm's
`meta.helm.sh/release-name`) — installing via Helm against objects created
by Kustomize fails with "invalid ownership metadata." Plan: finish
Kustomize deploy, add monitoring, then tear down and redeploy via Helm as a
deliberate comparison exercise (see §18).

---

## 10. Pod Pending / Node Provisioning Troubleshooting

All 7 pods stuck `Pending`, no node/IP assigned.

```bash
kubectl describe pod <pod> -n ecommerce | tail -20
```
Showed `FailedScheduling: 0/4 nodes are available: 4 node(s) had untolerated
taint(s)`, then `Nominated ... karpenter ...` (confirming AKS Automatic's
Node Auto Provisioning literally *is* Karpenter), then transient
`FailedMount ... driver name secrets-store.csi.k8s.io not found` retries
while the CSI driver DaemonSet finished starting on the brand-new node.
Resolved on its own once the new node came up and the CSI driver registered.

Re-check: `ecommerce-web` fully healthy; `ecommerce-api` restarting;
`sqlserver-0` in **CrashLoopBackOff** (next section).

---

## 11. SQL Server CrashLoopBackOff — Root Cause Deep Dive

```bash
kubectl logs sqlserver-0 -n ecommerce --previous --tail=30
```
```
/opt/mssql/bin/sqlservr: Error: The system directory [/.system] could not
be created. ... Access Denied errno = 0xD(13) Permission denied
```

Ruled out: pod-level `securityContext` restrictions (empty), Pod Security
admission labels (none set), sandboxing (plain `containerd`, no
Kata/gVisor).

**Debug technique used** — `kubectl debug --copy-to` was tried first but hit
its own Gatekeeper rejection (`Disallowed capabilities detected:
[SYS_PTRACE]`, from default process-namespace sharing), so instead: a
**minimal standalone debug Pod** was hand-written (same image,
`command: ["sleep","3600"]`, no volumes). This also needed explicit
`resources.requests/limits` added to pass the "every container needs
resource requests" Gatekeeper policy (same policy family hit repeatedly
throughout the session).

**Root cause, confirmed live from inside the debug pod:**
```
id            -> uid=10001(mssql)     # non-root by default in this SQL Server image version
ls -ld /      -> drwxr-xr-x root root  # only root can write to /
mkdir /.system            -> Permission denied   # exact match to the crash
mkdir /var/opt/mssql/x    -> succeeds             # proves it's not a broad lockdown
```
Microsoft's SQL Server image now defaults to a non-root `mssql` user, but
its own startup script still tries to `mkdir /.system` directly under `/`,
which requires root — a gap in the image's own non-root support. This is a
live example of why `:latest`-style unpinned images are dangerous: the same
tag pull months apart can behave completely differently.

**Fix:** added `securityContext: runAsUser: 0` to `sql-statefulset.yaml`
(the image's own internal logic still drops privileges for the actual DB
engine process afterward). Had to also `kubectl delete pod sqlserver-0 -n
ecommerce` to force recreation from the fixed template, since the
StatefulSet controller doesn't proactively replace an already-existing pod
just because its template changed.

---

## 12. API Pods Still Crashing — Missing Database

After SQL Server recovered, API pods stayed crashing.
```bash
kubectl delete pod -n ecommerce -l app.kubernetes.io/name=ecommerce-api
```
New crash trace: **SQL Error 4060** — "Cannot open database requested by the
login." TCP + auth succeeded; `ECommerceDb` simply didn't exist yet on the
brand-new server. By design, `Program.cs` only auto-migrates when
`IsDevelopment()`, and the ConfigMap sets `ASPNETCORE_ENVIRONMENT:
"Production"` (per the app's own README: migrations are meant to be a
controlled pipeline step, not automatic).

**Port-forward tooling detour (not a real infra bug):** attempted
`dotnet ef database update` through a `kubectl port-forward` tunnel to run
migrations manually. Hit repeated, inconsistent connection failures when the
port-forward was started via one tool call and the client connection
attempted via a separate one — traced to a harness quirk where background
port-forwards and foreground commands in this specific tool don't reliably
share a `localhost` binding across separate invocations. Not chased further
as a general lesson (harness-specific, not transferable).

**Pragmatic fix actually used:**
```bash
kubectl patch configmap ecommerce-config -n ecommerce --type merge \
  -p '{"data":{"ASPNETCORE_ENVIRONMENT":"Development"}}'
kubectl delete pod -n ecommerce -l app.kubernetes.io/name=ecommerce-api
```
ConfigMap changes never push into already-running containers — deleting the
pods forces a restart that picks up the new value. The app's own
`db.Database.Migrate()` (gated behind `IsDevelopment()`) created and seeded
the database. Confirmed via logs and all pods reaching `1/1 Ready`.

**Immediately reverted** back to `Production` + pod restart. **Why leaving
it on `Development` would be dangerous:** concurrent pods (e.g. after an HPA
scale-out) would each independently call `Migrate()` against the same live
database — a real race condition — and `Development` mode also exposes
Swagger UI and full stack-trace error pages, both security concerns in
production.

---

## 13. Private Endpoint for Azure SQL — Networking Deep Dive & the NRG Lockdown Wall

While briefly exploring a pivot to real Azure SQL (before reverting to fix
the in-cluster SQL Server above), investigated the AKS cluster's
auto-managed network:

```bash
az aks show -g rg-poc -n pocdevcluster --query nodeResourceGroup
# -> MC_rg-poc_pocdevcluster_swedencentral
az network vnet list -g MC_rg-poc_pocdevcluster_swedencentral
az resource list -g MC_rg-poc_pocdevcluster_swedencentral
```

Found: `aks-vnet-22862688` (`10.224.0.0/12`) with subnets for nodes, App
Gateway for Containers (delegated to
`Microsoft.ServiceNetworking/trafficControllers`), ACI virtual-node,
API-server VNet integration, and system pods — plus a NAT Gateway (outbound
internet with no public node IPs), a private `kube-apiserver` LB
(control-plane traffic), a public `kubernetes` LB (application traffic,
auto-wired whenever a `type: LoadBalancer` Service is created), and four
narrowly-scoped managed identities (kubelet, Key Vault CSI driver, Azure
Policy/Gatekeeper, Web App Routing).

**Attempted:** create a dedicated `private-endpoints-subnet` inside the AKS
VNet for a SQL Private Endpoint.

### Error: Deny Assignment blocks even Owner-level access

```
(DenyAssignmentAuthorizationFailed) ... denied because of the deny assignment
... node resource group deny assignment created by Azure Kubernetes Services
for nrg-lockdown
```

**Root cause:** AKS's **NRG lockdown** protects the entire auto-managed node
resource group with a **Deny Assignment** — a mechanism that always
overrides normal RBAC role grants, blocking even Owner-level external
principals from modifying AKS-owned infrastructure, including the VNet
itself.

**Attempted workaround:** create a separate VNet in `rg-poc` and peer it to
the AKS VNet — **also blocked**
(`LinkedAuthorizationFailed ... blocked by deny assignments on the linked
scope`), since Azure validates peering as a linked operation across both
VNets and the AKS side's deny assignment poisons the whole request even
though it originated on the unrestricted side.

**Senior-level conclusion:** this is a hard architectural wall specific to
AKS Automatic's "auto-generate everything" path. The real production fix is
**BYO VNet** — provision the VNet/subnets via Terraform *before* creating
AKS, then point AKS at an existing subnet (`--vnet-subnet-id`), so the VNet
is never inside AKS's own locked resource group; NRG lockdown then only ever
applies to node-level infra (VMs/NICs/disks/LBs), never the network. This
BYO-VNet pattern is exactly what the Terraform module built later (§36)
does.

**Decision:** skip Private Endpoint for this POC; the in-cluster SQL Server
fix (§11) was pursued instead of pursuing Azure SQL further.

---

## 14. End-to-End Validation (Kustomize deploy)

Ingress had no address — still referencing `ingressClassName: nginx`, but no
ingress-nginx controller was ever installed (this cluster uses AKS's managed
Web App Routing instead).

**Fix:** created `k8s/overlays/prod/patch-ingress-class.yaml` overriding
`ingressClassName: webapprouting.kubernetes.azure.com`.

### Error: Kustomize patch target not found

```
error: no matches for Id Ingress.v1.networking.k8s.io/ecommerce-ingress.[noNs]
... failed to find unique target for patch
```
**Root cause:** the patch file's `metadata` was missing
`namespace: ecommerce` — Kustomize matches patches by
Group/Version/Kind/Name/**Namespace** together. **Fix:** added the missing
namespace field.

```bash
kubectl apply -k k8s/overlays/prod
curl -sv http://<ingress-ip>/               # 200 OK, real Angular index.html
curl -sv http://<ingress-ip>/api/health     # 404 -- expected, /health has no /api prefix, meant for direct pod-IP probes
curl -sv http://<ingress-ip>/api/products   # 200 OK, real seeded JSON (6 products, 4 categories)
```
Confirmed the full path: Internet → Public IP → Azure LB → Web App Routing →
web Service → nginx pod → `proxy_pass` → api Service → API pod → EF Core →
SQL Server.

---

## 15. Custom Domain / Free Azure DNS Label

Attempted `az network public-ip update ... --dns-name ecommerce-poc-xp` on
the Web App Routing controller's own public IP — **hit the same NRG
lockdown deny assignment as §13** (this IP also lives in the locked node
resource group).

**Workaround found:** NRG lockdown blocks *external* principals (our own
`az`/Portal session) but not AKS's *own* cloud-provider component acting on
a Kubernetes-native request. The
`service.beta.kubernetes.io/azure-dns-label-name` annotation on a
`type: LoadBalancer` Service triggers AKS's own trusted identity to perform
the write, bypassing the lockdown entirely.

**Wrong first attempt:** a brand-new duplicate `LoadBalancer` Service with
the same pod selector as the existing `ecommerce-web` Service.
```
admission webhook "validation.gatekeeper.sh" denied ... same selector as
service <ecommerce-web> ... with overlapping ports
```
**Correct fix:** deleted the duplicate; instead created a **patch** on the
*existing* `ecommerce-web` Service, changing `spec.type: LoadBalancer` and
adding the DNS-label annotation directly — no duplicate object, no selector
conflict.

```bash
kubectl apply -k k8s/overlays/prod
az network public-ip list -g MC_rg-poc_... --query "[?ipAddress=='<ip>']..."
nslookup ecommerce-poc-xp.swedencentral.cloudapp.azure.com
```
Confirmed full DNS → IP → app flow.

**Architectural consequence flagged (left as a known trade-off, not fixed):**
this created a **second, independent public entry point** that completely
bypasses the Ingress layer — a Service's own `type` field controls
reachability regardless of any Ingress also referencing it. Any future
Ingress-only protections (WAF, TLS via cert-manager, path rules) would not
apply to this LoadBalancer path.

---

## 16. Git Auto-Commit Discovery

Before installing ArgoCD: `git status` unexpectedly showed a clean working
tree, already up to date with `origin/feature/ku8`, despite neither the user
nor the assistant ever running `git commit`/`git push` that session. `git
log` showed 5 commits matching exactly the session's work, confirmed present
on the real GitHub remote via `git fetch`. Very likely an IDE
auto-commit/auto-sync extension silently pushing work-in-progress changes —
flagged for the user to check their editor's Git settings. Practical upside:
content was already in Git, so ArgoCD could point at it with no extra step.

---

## 17. GitOps Concept / ArgoCD vs. Flux

Traditional CD is *push*-based (a human or pipeline runs `kubectl`/`helm`
commands). GitOps flips this to *pull*-based: a controller running inside
the cluster (ArgoCD) watches Git and reconciles automatically, and can
detect/revert drift ("self-heal") — Git becomes the actual source of truth,
not just a place code happens to live.

Compared ArgoCD (polished UI, pairs naturally with Argo Rollouts, very
common interview topic) vs. Flux (lighter, CRD-only, has its own built-in
image-automation-controller). **Chose ArgoCD.**

Also reviewed a separate reference project for hand-written ArgoCD patterns:
`AppProject` (scopes allowed repos/destinations/kinds — the *default*
project is unrestricted), the **app-of-apps** pattern (one root
`Application` pointing at a directory of child `Application` manifests so
they self-bootstrap), and a prod `Application` deliberately **omitting**
`syncPolicy.automated` (drift shows as `OutOfSync` but requires a manual
`argocd app sync` — mirrors a change-management approval gate). Even in that
more mature setup, ArgoCD's own control-plane objects are still installed
via the official manifest/Helm chart — only `Application`/`AppProject`
objects are ever hand-written.

---

## 18. Helm Chart Migration (from Kustomize)

Decision: convert to Helm *before* setting up ArgoCD, so ArgoCD only needs
configuring once, against the final setup.

Full chart rewrite in `helm/ecommerce-chart/` (existing chart was just the
untouched `helm create` scaffold, pointing at a placeholder `nginx` image):
- `values.yaml` — full rewrite: `namespace`, `serviceAccount` (Workload
  Identity clientId), `keyVault`, `config` (ConfigMap data), `api`/`web`/`sql`
  sections (image, resources, replicas, HPA, PDB).
- New templates: `namespace.yaml`, `secretproviderclass.yaml`,
  `configmap.yaml`, `api-deployment.yaml`, `api-service.yaml`, `api-hpa.yaml`,
  `api-pdb.yaml`, `web-deployment.yaml`, `web-service.yaml`,
  `sql-statefulset.yaml` (headless Service + StatefulSet, carrying over the
  `runAsUser: 0` fix from §11).
- Removed the generic scaffold `deployment.yaml`/`service.yaml`/`hpa.yaml`/
  `httproute.yaml`.

```bash
helm lint "helm/ecommerce-chart"                                    # clean
helm template ecommerce "helm/ecommerce-chart" > /tmp/helm-rendered.yaml
grep "^kind:" /tmp/helm-rendered.yaml                                # confirmed all 13 expected resource kinds
```

### Error 1: Duplicate label key breaks Deployment selector

```
Error: INSTALLATION FAILED: server-side apply failed for object
ecommerce/ecommerce-web ... Deployment.apps "ecommerce-web" is invalid:
spec.template.metadata.labels: Invalid value: ...: `selector` does not
match template `labels`
```
**Root cause:** templates set an explicit `app.kubernetes.io/name:
ecommerce-api` label *and* included a shared `ecommerce-chart.labels` helper
whose `selectorLabels` sub-template *also* sets `app.kubernetes.io/name` —
but to the chart's own name (`ecommerce-chart`). The duplicate map key let
the chart-name value leak into the pod template labels, no longer matching
the Deployment's `selector`.

**Fix:** introduced a dedicated selector label (`ecommerce.io/component:
api`/`web`) never reused for Helm's own chart-tracking labels, across every
affected Deployment/StatefulSet/Service.

### Error 2: Stale failed release blocks reinstall

```
Error: INSTALLATION FAILED: release name check failed: cannot reuse a name
that is still in use
```
**Root cause:** the first failed install left a release record with
`STATUS: failed` (no `-n` flag was passed, so it landed in `default`).
**Fix:** `helm uninstall ecommerce`, confirmed the namespace was empty, then
`helm install ecommerce helm/ecommerce-chart -n ecommerce --create-namespace`
— `STATUS: deployed`.

### Error 3: CrashLoopBackOff — fresh empty database

Same root cause as §12 (brand-new namespace = brand-new empty SQL PVC).
Same fix: toggle `ASPNETCORE_ENVIRONMENT` to `Development` via ConfigMap
patch, restart pods to let EF Core migrate, then flip it back.

### Error 4: `helm test` fails on an unpinned image

```
admission webhook "validation.gatekeeper.sh" denied the request: ... Please
specify an explicit version such as '1.0'.
```
**Root cause:** `templates/tests/test-connection.yaml` used `image: busybox`
(implicit `:latest`). **Fix:** pinned `image: busybox:1.36`.

**Teaching moment:** re-running `helm test` *still* failed with the exact
same error, because `helm test` (like all Helm hooks) runs against the
manifest **stored in the release's history**, not the live template files on
disk — editing a template has zero effect on an existing release until
`helm upgrade` actually runs.

### Error 5: Server-Side Apply conflict — HPA vs. Deployment both own `replicas`

```
error="conflict occurred while applying object ecommerce/ecommerce-api ...
conflict with \"kube-controller-manager\" with subresource \"scale\" ...
.spec.replicas"
```
**Root cause:** the HPA manages `ecommerce-api`'s replica count via the
Deployment's `/scale` subresource, making the HPA controller the
field-owner of `.spec.replicas` — but the Deployment template *also*
explicitly set `replicas:` on every apply. Two managers claiming the same
field under Server-Side Apply.

**Fix:** added `api.hpa.enabled: true` to `values.yaml`; wrapped
`replicas:` in the Deployment template with
`{{- if not .Values.api.hpa.enabled }}...{{- end }}` (omit it entirely when
HPA is enabled). `helm upgrade` then succeeded; `ecommerce-api` correctly
scaled down to `minReplicas` as expected HPA behavior, not a bug.

**Milestone:** Helm chart fully validated and deployed, with identical
runtime results to the earlier Kustomize deployment.

---

## 19. ArgoCD Installation

### Attempt 1 — raw manifest (failed)

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
Two of five components got stuck in `CreateContainerConfigError` — `kubectl
describe` showed `secret "argocd-redis" not found`, and several components
had Services but no matching Deployments/Pods at all (likely a partial apply
failure on a very large multi-object manifest).

Re-applying (idempotent) surfaced two deeper, non-retriable issues:
1. The `applicationsets.argoproj.io` CRD exceeded `kubectl apply`'s 262KB
   last-applied-configuration annotation limit (a client-side apply
   limitation).
2. ArgoCD's upstream init containers have no `resources.requests` set — hard
   rejected by this cluster's "every container needs resource requests"
   Gatekeeper policy (the same family hit in §11's debug pod).

**Decision:** rather than hand-patch a large unfamiliar third-party
manifest, switch to the **official Helm chart**, since Helm values allow
setting `resources:` per component including init containers.
`kubectl delete namespace argocd --wait=true` to reset for a clean
reinstall.

### Attempt 2 — via Helm (succeeded, after two more leftover-object errors)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update argo
```
Created `helm/values-argocd.yaml` with resource overrides for 13 empty
`resources: {}` blocks across ArgoCD's components (controller, dex, redis,
redisSecretInit, server, repoServer/copyutil, applicationSet,
notifications, commitServer) — same Gatekeeper reasoning as above.

#### Error: leftover cluster-scoped CRDs from Attempt 1

```
Error: INSTALLATION FAILED: unable to continue with install: CustomResource
Definition "applications.argoproj.io" ... exists and cannot be imported ...
invalid ownership metadata
```
**Root cause:** CRDs are **cluster-scoped**, not namespace-scoped — deleting
the `argocd` namespace in Attempt 1 never touched
`applications.argoproj.io`/`appprojects.argoproj.io`. Helm refuses to
"adopt" objects it doesn't already own.
**Fix:** `kubectl delete crd applications.argoproj.io appprojects.argoproj.io`

#### Error: leftover ClusterRoles (same pattern)

```
ClusterRole "argocd-application-controller" ... exists and cannot be
imported ... invalid ownership metadata
```
**Fix:**
```bash
kubectl delete clusterrole argocd-application-controller argocd-applicationset-controller argocd-server
kubectl delete clusterrolebinding argocd-application-controller argocd-applicationset-controller argocd-server
```

Retried the install → **`STATUS: deployed`**.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward service/argocd-server -n argocd 8080:443   # run via PowerShell, not Bash (see port-forward note in §12/§34)
```

---

## 20. AppProject and Application

**`argocd/project.yaml`** (AppProject `ecommerce`):
- `sourceRepos`: only this repo's URL.
- `destinations`: only the in-cluster API server + `ecommerce` namespace.
- `clusterResourceWhitelist`: explicitly only `{group: "", kind: Namespace}`
  (not a wildcard) — needed because the chart's own `namespace.yaml`
  template creates a cluster-scoped object; chose to keep that template
  rather than switch to ArgoCD's `CreateNamespace=true` sync option.
- `namespaceResourceWhitelist`: `{group: "*", kind: "*"}` (a learning-POC
  choice; production would enumerate exact kinds).

**`argocd/application.yaml`** (Application `ecommerce`):
- `source`: this repo, `targetRevision: feature/ku8`,
  `path: helm/ecommerce-chart` (auto-detected as a Helm chart via
  `Chart.yaml`).
- `syncPolicy.automated`: `prune: true`, `selfHeal: true` — explicitly the
  "learning" setting; production would omit `automated` for manual
  `argocd app sync` after change approval (mirrors §17's prod example).
- `syncOptions: [CreateNamespace=true]`.

```bash
kubectl apply -f argocd/project.yaml -f argocd/application.yaml
```

**Concept:** AppProject = the rulebook (what's *allowed*); Application = the
actual thing to deploy (what gets *created/synced*).

---

## 21. ArgoCD OutOfSync Troubleshooting

After apply: `SYNC STATUS: OutOfSync`, `HEALTH STATUS: Healthy`. Per-resource
check showed only the `ecommerce-web` Deployment as `OutOfSync`.

### Root cause #1: AKS's webhook injects fields that don't exist in Git

Comparing `helm template` output (desired) vs. `kubectl get deployment -o
yaml` (live) showed the live object had `affinity` and
`topologySpreadConstraints` blocks the chart never defines at all — AKS's
"deployment safeguards" mutating webhook auto-injects these on every
Deployment, a permanent, unfixable-from-Git diff.

**Fix attempt 1:** added an `ignoreDifferences` block to
`argocd/application.yaml` for those two paths. (First attempt didn't
actually take effect — the `kubectl apply` had silently never been
retried after an earlier rejection; confirmed via
`kubectl get application ecommerce -n argocd -o jsonpath='{.spec.ignoreDifferences}'`
returning empty.)

### Root cause #2: the webhook ALSO mutates resource requests — infinite self-heal loop

Even after properly applying fix #1, still `OutOfSync`. Comparing resources
specifically: chart said `requests.cpu: 50m`, live showed `100m` (AKS
bumping it as a QoS-safety minimum).

**Mechanism:** with `selfHeal: true`, ArgoCD kept re-applying `50m`; AKS's
webhook kept re-bumping it to `100m` immediately after — an infinite fight,
visible live in controller logs as a climbing `SelfHealAttemptsCount`.

**Fix:** extended `ignoreDifferences` to also cover
`/spec/template/spec/containers/0/resources`. Re-applied, hard-refreshed
(`kubectl annotate application ecommerce -n argocd
argocd.argoproj.io/refresh=hard --overwrite`) → **`Synced` / `Healthy`**,
confirmed stable.

**Standard pattern learned:** `ignoreDifferences` is the correct tool for
any field an admission webhook/other controller injects that will never
match Git through no fault of the chart author — don't fight it, tell
ArgoCD to ignore it.

---

## 22. Monitoring Stack (kube-prometheus-stack via Helm)

Cluster already had Azure Monitor managed Prometheus enabled — chose to
self-host `kube-prometheus-stack` anyway for genuine hands-on Prometheus/
Grafana skills separate from the managed flavor.

**Concept:** Prometheus *pulls* (scrapes) metrics from targets on a
schedule; Grafana is purely a visualization layer querying Prometheus via
PromQL — it stores nothing itself.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
```
Created `helm/values-monitoring.yaml` with resource overrides (same
Gatekeeper "no empty resources" reasoning as ArgoCD).

### Error: three structural AKS incompatibilities, all in one failed install

```bash
helm install monitoring prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f helm/values-monitoring.yaml
```
1. `aks-managed-protect-system-namespaces` denied Services in `kube-system`
   for scraping `kube-controller-manager`/`kube-scheduler`/`coredns`/
   `kube-proxy`/`kube-etcd` directly.
2. `aks-managed-baseline-hostpath-volumes` denied the `node-exporter`
   DaemonSet's HostPath mounts (`/proc`, `/sys`, `/`).
3. Permission denied creating/modifying the
   `MutatingWebhookConfiguration` for admission — restricted to trusted
   system principals on AKS.

**Root cause (each genuinely structural, not just a permissions
inconvenience):**
1. AKS's control plane is Microsoft-managed, hidden infrastructure — these
   Services would have nothing real to scrape even if allowed.
2. `node-exporter`'s entire design requires HostPath mounts to read raw
   node hardware/OS metrics — a classic container-escape vector AKS's
   baseline security policy blocks outright.
3. Cluster-wide `MutatingWebhookConfiguration` objects are restricted to
   trusted system principals.

**Fix:** disabled all three families in `values-monitoring.yaml` —
`kubeControllerManager`, `kubeScheduler`, `kubeEtcd`, `kubeProxy`,
`coreDns`, `nodeExporter`, `prometheus-node-exporter`, each set to
`enabled: false`, documented with a comment explicitly noting these are
*not* cost-cutting, they're genuine incompatibilities not meant to be
bypassed.

### Error: failed release can't be uninstalled OR upgraded

`helm uninstall` failed trying to clean up a `MutatingWebhookConfiguration`
that never actually got created (permission denied on delete, same as
create). `helm upgrade` failed with `"monitoring" has no deployed releases`
(Helm requires at least one successful revision to upgrade from).

**Fix:** confirmed the webhook config genuinely didn't exist
(`kubectl get mutatingwebhookconfiguration ... -> NotFound`), then
`kubectl delete namespace monitoring --wait=true` for a full reset (also
clears Helm's release-tracking Secret), checked for leftover cluster-scoped
CRDs/ClusterRoles (none this time), retried the install fresh with corrected
values → `STATUS: deployed`.

### ServiceMonitor investigation

`kubectl get servicemonitors.monitoring.coreos.com -n monitoring` initially
returned nothing despite a successful Helm release. Isolated by extracting
one ServiceMonitor from `helm get manifest` and applying it directly with
plain `kubectl apply` — worked immediately, confirming the CRD/cluster
mechanics were fine and the issue was specific to how the aggregate
Helm-managed manifest was being applied (resolved via re-running `helm
upgrade`).

```bash
kubectl --namespace monitoring get secrets monitoring-grafana -o jsonpath="{.data.admin-password}" | base64 -d
kubectl port-forward svc/monitoring-kube-prometheus-prometheus -n monitoring 9090:9090
kubectl port-forward svc/monitoring-kube-state-metrics -n monitoring 8090:8080
```

---

## 23. Application Instrumentation (Prometheus metrics on ecommerce-api)

Added `prometheus-net.AspNetCore` NuGet package; wired `UseHttpMetrics()`/
`MapMetrics()` into `Program.cs` to expose a `/metrics` endpoint.

```bash
dotnet build backend/src/ECommerce.Api          # 0 warnings, 0 errors
```

Created `helm/ecommerce-chart/templates/api-servicemonitor.yaml`; also fixed
`api-service.yaml` to carry the `ecommerce.io/component: api` label on the
**Service's own metadata** (it was previously only on the pod selector, so
nothing could select the Service by that label for scraping).

```bash
docker build -t acrecommercepoc.azurecr.io/ecommerce-api:1.1.0 -f backend/dockerfile backend
docker push acrecommercepoc.azurecr.io/ecommerce-api:1.1.0
```

### Error: ACR auth expired

```
error from registry: authentication required
```
**Root cause:** ACR login token expired after many hours of session
runtime. **Fix:** `az acr login -n acrecommercepoc`, retried push.

Committed and pushed (`feat(api): add Prometheus metrics endpoint via
prometheus-net.AspNetCore`). ArgoCD's default poll interval (~3 min) meant
the tracked revision was initially stale — forced immediate pickup:
```bash
kubectl annotate application ecommerce -n argocd argocd.argoproj.io/refresh=hard --overwrite
```
**Full GitOps loop confirmed working end-to-end:** commit → push → ArgoCD
auto-sync → new image live → metrics scrapeable.

---

## 24. PromQL / Grafana

Generated test traffic (`curl` loops against `/api/products`,
`/api/categories`) to have real data to query.

```promql
http_requests_received_total{job="ecommerce-api"}
```
The `prometheus-net` middleware auto-tracks this **counter** (only ever
increases, resets only on process restart) per request, broken down by
`code`/`method`/`controller`/`action`.

```promql
rate(http_requests_received_total{job="ecommerce-api"}[5m])
```
Turns a raw ever-growing counter into a per-second average rate over the
trailing window — shorter windows react faster but are noisier.

```promql
sum(rate(http_requests_received_total{job="ecommerce-api"}[5m])) by (exported_endpoint)
```
Aggregates away per-pod noise while keeping a per-endpoint breakdown.

**Teaching point:** two flat baseline lines (~0.20 and ~0.133 req/s) turned
out to be Kubernetes' own readiness (every 10s) and liveness (every 15s)
probes across 2 pods — not real traffic. Real test traffic showed as small
bumps that decayed after 5 minutes as the `rate()` window aged them out,
illustrating that `rate()` always describes a moving window, never a
permanent record.

**Standard senior-level practice — exclude health-check noise:**
```promql
sum(rate(http_requests_received_total{job="ecommerce-api", exported_endpoint!~"/health.*"}[5m])) by (exported_endpoint)
```

**Grafana:**
```bash
kubectl get secret --namespace monitoring -l app.kubernetes.io/component=admin-secret -o jsonpath="{.items[0].data.admin-password}" | base64 --decode
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80   # via PowerShell
```
No separate `helm repo add grafana` step was ever needed — `kube-prometheus-
stack` bundles Prometheus, Alertmanager, the Prometheus Operator,
kube-state-metrics, and Grafana as sub-charts in one release, so Grafana
already had Prometheus pre-wired as a data source.

(Minor snag: briefly tried `localhost:3001` due to an unrelated process also
listening there — the real port-forward target was `3000`.)

---

## 25. Log Analytics / KQL

```bash
az aks show -g rg-poc -n pocdevcluster --query "addonProfiles.omsagent"
az monitor log-analytics workspace list --query "[].{name:name, resourceGroup:resourceGroup}"
# -> found poclogworkspace in DefaultResourceGroup-EUS (different RG than expected)
```
Confirmed wiring: `omsAgent.enabled: true`, pointing at that workspace, with
`useAADAuth: true` (secretless, same pattern as the rest of the session).

### Error: CLI extension prompt in a non-interactive shell

```
EOFError: EOF when reading a line
```
**Root cause:** the `log-analytics` CLI extension wasn't installed, and
`az` tried to interactively prompt to install it. **Fix:**
`az extension add --name log-analytics --yes` first.

```bash
az monitor log-analytics workspace show -g DefaultResourceGroup-EUS -n poclogworkspace --query "customerId" -o tsv
az monitor log-analytics query -w <workspace-id> --analytics-query "
  ContainerLogV2
  | where PodNamespace == 'ecommerce' and ContainerName == 'api'
  | where TimeGenerated > ago(1h)
  | project TimeGenerated, PodName, LogMessage
  | sort by TimeGenerated desc | take 20
" -o table
```
Results showed EF Core `SELECT 1` log lines from the `/health` readiness
probe — the same underlying activity seen earlier via metrics, now via
logs (metrics vs. logs vs. traces as complementary views on the same
system).

```kql
ContainerLogV2
| where PodNamespace == "ecommerce" and ContainerName == "api"
| where TimeGenerated > ago(30m)
| summarize LogCount = count() by PodName, bin(TimeGenerated, 1m)
| sort by TimeGenerated desc
```
(`summarize`/`bin` = KQL's `GROUP BY` + time-bucketing.)

---

## 26. Deployment Strategies — Concepts

- **Rolling Update**: Kubernetes' built-in `Deployment` strategy —
  `maxSurge`/`maxUnavailable` control gradual, eventual, all-or-nothing
  replacement. No partial/permanent traffic split is possible.
- **Blue-Green**: two full environments; instant atomic cutover via a
  Service selector flip; needs ~2x capacity temporarily; zero real-user risk
  until the actual cutover moment, but still all-or-nothing traffic-wise.
- **Canary**: gradual weighted traffic shift (e.g. 20% → 50% → 100%) with
  pause/inspect steps in between — safest for risky changes, but requires a
  controller capable of shifting percentages; a plain `Deployment` cannot do
  this at all.

**Naming clarified** (a common point of confusion): "Rolling Update" is a
*strategy* (an algorithm); "Rollout" is a Kubernetes *object type* (Argo's
CRD, which replaces `Deployment`); "a rollout" (lowercase, generic) is just
the general act of deploying an update — a term that predates Argo Rollouts
entirely.

**Design decision:** since one Rollout/Deployment can only run one strategy
at a time, `ecommerce-web` stays a plain `Deployment` with explicit Rolling
Update parameters (an always-live comparison point), while `ecommerce-api`
becomes an Argo Rollouts `Rollout` with a `values.yaml` toggle between
`canary` and `blueGreen` — both fully written and switchable, only one
active at a time.

---

## 27. Installing Argo Rollouts

```bash
helm search repo argo/argo-rollouts     # confirmed available (chart 2.41.1)
helm show values argo/argo-rollouts > /tmp/rollouts-values.yaml
grep -n "resources: {}" /tmp/rollouts-values.yaml   # same empty-resources pattern as every other chart this session
```
Created `helm/values-argo-rollouts.yaml`:
```yaml
controller:
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits: { cpu: 200m, memory: 256Mi }
dashboard:
  resources:
    requests: { cpu: 25m, memory: 64Mi }
    limits: { cpu: 100m, memory: 128Mi }
```
```bash
helm install argo-rollouts argo/argo-rollouts -n argo-rollouts --create-namespace -f helm/values-argo-rollouts.yaml
```
Installed cleanly on the first try. (Note: the `kubectl-argo-rollouts` CLI
plugin was never actually installed — this matters later in §30.)

---

## 28. Converting ecommerce-api to a Rollout

`helm/ecommerce-chart/templates/api-deployment.yaml`:
`apiVersion: apps/v1 / kind: Deployment` → `apiVersion: argoproj.io/v1alpha1
/ kind: Rollout`, with `spec.strategy` templated to switch between
`canary`/`blueGreen` based on `.Values.api.strategy`.

`web-deployment.yaml`: added an **explicit** Rolling Update strategy
(`maxSurge: 1, maxUnavailable: 0`) instead of relying on Kubernetes' silent
25%/25% default — makes pod-by-pod behavior observable, and gives
`ecommerce-web` its role as the permanent Rolling-Update comparison point.

`values.yaml` additions:
```yaml
api:
  strategy: canary   # or "blueGreen"
  canary:
    steps:
      - setWeight: 20
      - pause: { duration: 30s }
      - setWeight: 50
      - pause: { duration: 30s }
      - setWeight: 100
  blueGreen:
    autoPromotionEnabled: false
```
New file `api-service-preview.yaml` — a `{{- if eq .Values.api.strategy
"blueGreen" }}` conditional Service (`ecommerce-api-preview`) used only by
blue-green.

`api-hpa.yaml`: `scaleTargetRef.kind` changed from `Deployment` to
`Rollout` (`argoproj.io/v1alpha1`) — Argo Rollouts supports being an HPA
target under this different kind.

```bash
helm lint helm/ecommerce-chart
helm template ecommerce helm/ecommerce-chart --show-only templates/api-deployment.yaml               # canary (default)
helm template ecommerce helm/ecommerce-chart --show-only templates/api-deployment.yaml --set api.strategy=blueGreen   # blueGreen
```
Both rendered correctly; confirmed the preview Service only appears under
`blueGreen`. Committed and pushed; forced ArgoCD refresh.

---

## 29. Incident 1 — Stuck at 1/2 Replicas

`kubectl get deployment,rollout -n ecommerce` showed `DESIRED: 2, CURRENT:
1` indefinitely.

**Reusable debug checklist used:**
```bash
kubectl get deployment,rollout -n ecommerce
kubectl get pods -n ecommerce -l ecommerce.io/component=api
kubectl describe rollout ecommerce-api -n ecommerce
kubectl get hpa ecommerce-api-hpa -n ecommerce
kubectl get replicaset -n ecommerce -o wide
kubectl logs -n argo-rollouts -l app.kubernetes.io/name=argo-rollouts --tail=50 | grep -i "ecommerce-api"
```
The last command found the actual rejection:
```
admission webhook "validation.gatekeeper.sh" denied the request:
[azurepolicy-k8sazurev1antiaffinityrules-...] ReplicaSet with 2 replicas
should have either podAntiAffinity or topologySpreadConstraints set to
avoid disruptions due to nodes crashing.
```

**Root cause:** AKS's mutating "deployment safeguards" webhook auto-injects
anti-affinity/topology-spread only on standard workload kinds
(`Deployment`/`StatefulSet`/`DaemonSet`) — it does not recognize the custom
`Rollout` CRD's pod template, so the free auto-mutation never fires. The
*separate*, independent validating policy requiring one of those settings
still applies regardless of what created the ReplicaSet.

**Fix:** added explicitly to the Rollout's pod template:
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        ecommerce.io/component: api
```
Validated (`helm lint`, `helm template ... | grep -A6
topologySpreadConstraints`), committed, pushed.

**Side lesson on HPA math:** the HPA's `SuccessfulRescale` to `2` fired
purely from `minReplicas` floor, unrelated to the (1%) CPU utilization at
the time — `minReplicas`/`maxReplicas` are a hard floor/ceiling independent
of whatever the CPU target is doing.

---

## 30. Incident 2 — Old ReplicaSet Permanently Stuck

After the §29 fix landed, ArgoCD synced to the new commit, but pod count
still didn't reach 2. A *new* ReplicaSet (with the fix) appeared with **0**
desired pods and no events, while the *old* ReplicaSet kept retrying.

**Root cause** (from controller logs): at 20% canary weight with only 2
total desired pods, the canary math rounded the canary share **down to
zero**, so Argo Rollouts tried to grow the **old, pre-fix** ReplicaSet from
1→2 to carry the full load — but that ReplicaSet's pod template is
**immutable** (created before the fix), so it can never legally hold 2
replicas; Gatekeeper rejected the scale-up every ~10 seconds, forever.

**Fix:** force full promotion to skip the stuck canary math and cut over
entirely to the new (fixed) ReplicaSet.

```bash
kubectl argo rollouts promote ecommerce-api -n ecommerce --full
```
```
error: unknown command "argo" for "kubectl"
```
The `kubectl-argo-rollouts` plugin was never installed (§27 note). Worked
around by directly patching the status field the plugin would have set:
```bash
kubectl patch rollout ecommerce-api -n ecommerce --subresource=status --type=merge -p '{"status":{"promoteFull":true}}'
```
(First attempt with escaped `\"` quotes failed with `invalid character
'\\'` — PowerShell single-quoted strings are literal, no backslash-escaping
needed inside them.)

**Verified:** pods scaled to 2/2 across 2 different nodes, old ReplicaSet
scaled to 0,
```bash
kubectl get rollout ecommerce-api -n ecommerce -o jsonpath="{.status.phase} promoteFull={.status.promoteFull}"
# -> Healthy promoteFull=       (the field is one-shot, self-clears after use)
```

---

## 31. Watching a Live Canary (1.2.0 → 1.3.0)

Retagged an existing image server-side instead of rebuilding — the whole
point was to exercise the canary mechanics, not test new app code:
```bash
az acr import --name acrecommercepoc --source acrecommercepoc.azurecr.io/ecommerce-api:1.1.0 --image ecommerce-api:1.2.0
```
Bumped `values.yaml`'s tag, committed, pushed, forced ArgoCD refresh.

**First attempt:** the 30-second pauses completed before there was any
chance to observe them mid-flight — `kubectl describe rollout` already
showed `Phase: Healthy` by the time anyone looked.

**Fix for observability:** bumped pause durations to 120s (alongside
another tag bump to `1.3.0`) — long enough to actually watch.

**Watched live** using a background polling loop (`kubectl get rollout -o
jsonpath=...` on a `sleep 5` cycle, exiting once `phase=Healthy` — chosen
over a blocking `sleep`+command chain, which this harness explicitly
disallows). Progression observed:
- `step=1 phase=Paused` — 20% (1 old + 1 new pod)
- `step=3 phase=Paused` — 50% (confirmed via `stableRS`/`currentPodHash`)
- `step=5 phase=Healthy` — 100%, fully cut over

**Reliable way to tell old vs. new pods:** compare each ReplicaSet's
`rollouts-pod-template-hash` label against the Rollout's own
`status.stableRS` (= old) and `status.currentPodHash` (= new) — never by
ReplicaSet age, since "old" and "new" are relative and swap every rollout;
today's "new" becomes tomorrow's "old" the moment the next deploy happens.

**`kubectl get rollout -w` column semantics:**
| Column | Meaning |
|---|---|
| `DESIRED` | how many pods you eventually want (never changes mid-rollout) |
| `CURRENT` | how many pods physically exist right now (old + new combined) |
| `UP-TO-DATE` | how many match the *newest* pod template |
| `AVAILABLE` | how many are ready/serving traffic (old + new combined) |

**The key insight, from controller logs:**
```
msg="No TrafficRouting Reconcilers found"
```
This cluster has no Istio/SMI/AGIC-style traffic-splitting installed, so
Argo Rollouts falls back to **"basic canary"**: it approximates a weight
percentage purely by controlling how many *pods* of each version exist, then
trusts the Kubernetes Service to load-balance roughly evenly across whatever
pods match its selector. This is why "20%" with only 2-3 total pods actually
behaves closer to ~33% — a real, known rounding limitation at low replica
counts, and the core argument for real traffic-routing integrations in
production (a service mesh or Application Gateway with true percentage-based
routing, independent of pod counts).

---

## 32. Watching Blue-Green (1.4.0 → preview → 1.5.0)

Flipped `values.yaml`: `api.strategy: canary` → `blueGreen`, bumped tag to
`1.4.0`, committed, pushed.

### Error: preview Service creation rejected

ArgoCD Application went `OutOfSync`, Rollout `Degraded`:
```
The Rollout "ecommerce-api" is invalid: spec.strategy.blueGreen.previewService:
Invalid value: "ecommerce-api-preview": service "ecommerce-api-preview" not found
```
Digging into ArgoCD's actual sync operation result revealed the real error:
```
admission webhook "validation.gatekeeper.sh" denied the request:
[azurepolicy-k8sazurev1uniqueserviceselecto-...] same selector as service
<ecommerce-api> in namespace <ecommerce> with overlapping ports.
```
**Root cause:** vanilla Argo Rollouts blue-green intentionally creates the
preview Service with the *same* selector/port as the active Service
initially, then patches in a distinguishing `rollouts-pod-template-hash`
label **after** creation — but AKS's `uniqueServiceSelectors` Gatekeeper
policy rejects the very first creation before that patch can ever happen.

Read the actual policy source
(`kubectl get constrainttemplate k8sazurev1uniqueserviceselector -o
jsonpath="{.spec.targets[0].rego}"`) and confirmed it only compares
`spec.ports[].port` (the exposed port number), never `targetPort`.

**Fix:** changed the preview Service's exposed port from `8080` to `8081`
(keeping `targetPort: 8080`, so it still reaches the identical pods) —
sidesteps the selector+port collision entirely without changing any real
routing behavior. Committed, pushed, forced refresh.

**"First-time" behavior repeated:** after the fix, the first blue-green sync
went straight to `Healthy` with no pause — switching *strategy type* itself
resets the Rollout's context, so it's treated as establishing a fresh
baseline rather than a real update (same pattern noted for canary in §31).

**Triggered a genuine update** by tagging `1.5.0`, bumping `values.yaml`,
pushing. Watched via the same polling-loop technique until `phase=Paused`:
```bash
kubectl get pods -n ecommerce -l ecommerce.io/component=api -L rollouts-pod-template-hash
kubectl get svc ecommerce-api ecommerce-api-preview -o custom-columns=NAME:.metadata.name,SELECTOR:.spec.selector
```
Result: **4 pods total** — 2 old + 2 new, *all still running* (unlike
canary, blue-green never kills the old pods automatically). `ecommerce-api`
(port 8080) selector locked to the old hash; `ecommerce-api-preview` (port
8081) selector locked to the new hash. Nothing auto-promoted, since
`autoPromotionEnabled: false`.

**Verified the preview independently** — the core value proposition of
blue-green:
```bash
kubectl -n ecommerce port-forward svc/ecommerce-api-preview 8081:8081
curl http://localhost:8081/health        # Healthy
curl http://localhost:8081/health/live   # Healthy
```
Real production traffic on `ecommerce-api:8080` never saw the new version
at any point during this check — full verification with zero real-user
exposure before deciding to promote.

---

## 33. Security Incident — Leaked Credential in Git History

A commit made during the canary work (bumping pause durations/tag)
accidentally swept in an unrelated `README.md` change — a running personal
command journal the user had been keeping — which contained a **plaintext
decoded ArgoCD admin password**, already pushed to GitHub.

**Redacted here on purpose:** the actual password value is intentionally
*not* reproduced in this document. Treat it as permanently compromised
regardless of repo visibility.

**Recommended and later carried out:** rotate the ArgoCD admin password
(§34) — treat the leaked one as burned. A full git-history rewrite
(`git filter-repo`/interactive rebase) was also flagged as worth doing if
the repo is public, since deleting the line in a new commit does not remove
it from history.

**Lesson:** always review exactly what's staged before committing
(`git status`/`git diff` after any broad `git add`), especially when a
personal notes file sits in the same repo as real infrastructure work —
it's an easy, easy way for a real secret to slip into a commit meant to be
about something else entirely.

---

## 34. ArgoCD Admin Password Reset

Separate incident: logging into the ArgoCD UI with the password from
`argocd-initial-admin-secret` returned "invalid username" (and, on the
second attempt, invalid for the password too).

**Root cause:** the admin password had been rotated (or otherwise no longer
matched) at some point, making the leftover `argocd-initial-admin-secret`
Secret stale — it only ever holds the password from the moment ArgoCD was
first installed, and never seemed to have been kept in sync.

**Fix — ArgoCD's own documented "forgot the admin password" procedure:**
```bash
kubectl -n argocd delete secret argocd-initial-admin-secret --ignore-not-found
kubectl -n argocd patch secret argocd-secret --type merge -p '{"data":{"admin.password":null,"admin.passwordMtime":null}}'
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=90s
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}"   # freshly regenerated
```
Clearing the stored password hash and restarting the server makes ArgoCD
regenerate a brand-new password exactly as if this were a fresh install,
writing it back into `argocd-initial-admin-secret`. (The value itself is
not reproduced here — retrieve the current one directly from the cluster
with the command above whenever needed, rather than trusting any
previously-written-down value.)

### Follow-up error: "Request has been terminated" in the browser

**Root cause:** a stale `kubectl port-forward svc/argocd-server` tunnel,
pinned to the specific pod IP that had just been restarted out of existence.
`kubectl port-forward` against a Service locks onto one pod at start and
does not auto-reconnect if that pod goes away — confirmed via
`Get-CimInstance Win32_Process -Filter "Name = 'kubectl.exe'"` showing no
argocd-server forward still running, and `kubectl -n argocd get svc
argocd-server` confirming it's `ClusterIP` (no public entry point, a
port-forward is the only way in). **Fix:** simply start a fresh
port-forward.

---

## 35. Infrastructure Teardown Decision

With the deployment-strategies module wrapped up, weighed deleting the AKS
infra to stop billing.

**Cost drivers identified:** AKS node VMs (dominant cost), the
`ecommerce-web` LoadBalancer's public IP; ACR/Key Vault cost is
near-negligible by comparison. Everything built (Helm charts, ArgoCD
Application/AppProject, Rollout config) is defined as code in this repo —
deleting the cluster loses no conceptual work, only live running state and
the retagged ACR images (`1.2.0`–`1.5.0`, trivially recreatable via `az acr
import`).

**Decision: delete the whole resource group**, explicitly to force writing
real Terraform next, to recreate everything from code rather than by hand
again.

```bash
az resource list --resource-group rg-poc --output table
```
Flagged `vnet-shared-services` before deleting — its name suggested it
might be intended for reuse beyond this POC, not exclusive to it; confirmed
with the user it was fine to delete anyway.

```bash
az group exists --name rg-poc              # returned true (deletion still in progress)
az group show --name rg-poc --query properties.provisioningState -o tsv
# -> ERROR: (ResourceGroupNotFound) -- confirmed fully gone
```

---

## 36. Terraform Module

### Design decisions made up front
- AKS SKU: **classic AKS**, mirroring the exact prior configuration (Azure
  CNI Overlay, Cilium, Web App Routing, Workload Identity/OIDC, Azure
  Policy add-on) — not AKS Automatic, so the module has explicit control
  over every setting rather than inheriting Automatic's opinionated
  defaults.
- Azure Managed Grafana/Prometheus: **skipped** — the self-hosted
  `kube-prometheus-stack` from §22 already covers this; no need to
  duplicate it as a separate Azure-native resource.
- State backend: chosen as **local state file** initially for the POC,
  later revisited (see restructure below).

### Fundamentals
- **Provider** — a plugin that knows how to talk to one specific API
  (`azurerm` → Azure Resource Manager, the same API the `az` CLI hits).
- **Resource blocks** — declare desired state; Terraform diffs against
  reality and figures out what to create/change/destroy.
- **State file** — Terraform's own record of what it created and their
  real Azure resource IDs. Losing it means losing track of ownership
  entirely.
- Workflow: `terraform init` (download provider) → `terraform plan`
  (dry-run diff) → `terraform apply` (actually do it).

### First pass — flat structure (later replaced)

Wrote `versions.tf`, `providers.tf`, `variables.tf`, `main.tf` (resource
group + VNet + 2 subnets), `acr.tf`, `keyvault.tf`, `identity.tf`, `aks.tf`,
`role_assignments.tf`, `outputs.tf`.

```bash
terraform init -input=false     # downloaded hashicorp/azurerm v4.81.0 (satisfying the ~> 4.0 pin)
terraform validate
```

Real, authoritative schema errors caught by `validate` (not guessed):
- `enable_rbac_authorization` on `azurerm_key_vault` — deprecated, renamed
  to `rbac_authorization_enabled` in this provider version.
- `vnet_integration_enabled` on `api_server_access_profile` — `Error:
  Unsupported argument` (wrong field name entirely).
- `azure_active_directory_role_based_access_control { azure_rbac_enabled =
  true }` — `Error: Missing required argument`, needed an explicit
  `tenant_id` alongside it.

After fixing those three, `terraform validate` passed — but a subsequent
**real `terraform plan`** (read-only, against live Azure) caught something
`validate` structurally *cannot*: the plan showed
`virtual_network_integration_enabled = false` under
`api_server_access_profile`, even though `subnet_id` was set. **This proved
that simply setting `subnet_id` does not actually enable API Server VNet
Integration** — there's a real, separate boolean field, just under a
slightly different name (`virtual_network_integration_enabled`, not the
`vnet_integration_enabled` that had been guessed and rejected earlier).
Fixed by adding it explicitly with `= true`, then re-confirmed via another
plan that it now showed correctly.

**Lesson generalized:** `terraform validate` only checks schema/type
correctness; it cannot catch "valid HCL that silently does the wrong
thing." A real `plan` against the live API is the only way to catch that
class of bug before `apply`.

Final flat-structure plan: `12 to add, 0 to change, 0 to destroy`, zero
warnings.

### Restructure — modules + environments (final structure)

Prompted by explicit feedback: production practice requires modules, a
non-hardcoded backend, and environment segregation.

```
terraform/
  modules/
    network/    -- VNet + AKS subnet + delegated API-server subnet
    acr/
    key_vault/  -- RBAC-mode; purge_protection now a per-environment variable, not hardcoded
    identity/   -- user-assigned identity + federated credential + Key Vault Secrets User role
    aks/        -- the cluster itself
  environments/
    dev/   -> rg-poc-dev,  Free tier,     2 nodes, Standard_D2s_v5, purge protection OFF, VNet 10.10.0.0/16
    prod/  -> rg-poc-prod, Standard tier, 3 nodes, Standard_D4s_v5, purge protection ON,  VNet 10.20.0.0/16
```

**Backend, deliberately left blank:** each environment's `backend.tf`
declares an empty `backend "azurerm" {}` block. Real values (storage
account, container, state key) are supplied later at `terraform init
-backend-config=backend.hcl` time — never hardcoded in a committed `.tf`
file. A `backend.hcl.example` documents the required keys
(`resource_group_name`, `storage_account_name`, `container_name`, and a
`key` unique per environment, e.g. `dev/ecommerce.tfstate` vs.
`prod/ecommerce.tfstate` — this is what keeps two environments' state from
overwriting each other even if they share one storage account). Both
`backend.hcl` (real) and `terraform.tfvars` (real) are gitignored, mirroring
the existing `*.tfvars`/`!*.tfvars.example` pattern already in this repo's
`.gitignore`.

**Design fix caught mid-build:** the `key_vault` module initially hardcoded
`purge_protection_enabled = false`. Correct for dev (allows full
destroy/recreate cycles) but wrong for prod (a stray `destroy` should never
be able to permanently purge real secrets). Made it a module variable —
`false` in dev's call, `true` in prod's.

**Naming consequence:** the resource group was renamed from the original
`rg-poc` to `rg-poc-dev` (plus a new `rg-poc-prod`) — unavoidable once
"dev" and "prod" became real, separate concepts. ACR and Key Vault names
also had to differ between environments (`acrecommercepocdev` vs.
`acrecommercepocprod`, etc.) since both are globally-unique-name resource
types in Azure.

**Validation without a resolved backend** (since backend values are
intentionally blank until a real storage account exists):
```bash
cd environments/dev
terraform init -backend=false -input=false    # resolves the 5 local modules + provider, skips backend entirely
terraform validate                             # Success!
# same for environments/prod
terraform fmt -recursive -diff                 # from the terraform/ root, auto-fixed alignment in both environments
terraform fmt -recursive -check -diff          # exit 0 -- fully formatted
```

**Explicit trade-off called out, not hidden:** `dev` and `prod` duplicate
their root `.tf` file *plumbing* (not the module logic itself) — Terraform
has no built-in "inherit from a shared environment template" mechanism.
Tools like Terragrunt solve exactly this DRY problem, but weren't
introduced here since the user didn't ask for extra tooling.

**Known limitation at time of writing:** Terraform has been thoroughly
validated (`init`, `validate`, `fmt`, and a real read-only `plan` against
live Azure for the original flat structure) but **never actually applied**
— no live `terraform apply`/`destroy` cycle has been run against the
modularized `environments/dev` or `environments/prod` yet.

---

## 37. Cheat Sheets / Quick Reference

**Control plane vs. agent pool:** Control plane = API server + etcd +
scheduler + controller-manager, Azure-managed, no visible VM. Agent pool =
worker node VMs, visible in the `MC_...` resource group, where pods actually
run. Kubelet = the per-node agent that pulls images and starts containers.

**Two AKS load balancers:** `kube-apiserver` LB = Kubernetes managing
itself, privately (control-plane traffic). `kubernetes` LB = the public
front door to whatever you've deployed (application traffic).

**Two ACR-adjacent identities:** the control-plane identity manages Azure
infra *around* the cluster; the kubelet identity is the *only* one that
authenticates to ACR for image pulls.

**Old vs. new pod hash, reliably:** compare a ReplicaSet's
`rollouts-pod-template-hash` against the Rollout's own `status.stableRS`
(old) / `status.currentPodHash` (new) — never by age; the labels swap
meaning every rollout.

**`ignoreDifferences` in ArgoCD:** the correct tool whenever an admission
webhook or another controller injects a field that will never match Git
through no fault of your own manifest.

**Windows/Git Bash gotchas hit repeatedly this session:**
- `MSYS_NO_PATHCONV=1` prefix — needed any time an `az` command argument
  looks like a Unix absolute path (e.g. `/subscriptions/...`).
- cmd.exe does not strip single quotes — always use double quotes for
  values containing spaces/special characters in cmd.exe.
- PowerShell single-quoted strings are fully literal — no backslash
  escaping needed inside them (unlike Bash).
- `kubectl port-forward` against a Service locks onto one pod's IP at
  start and does not auto-reconnect if that pod is replaced — restart the
  forward after any rollout/restart of the target.

---

## 38. Gaps vs. Senior DevOps Market Standard (as of this session)

Recorded as an honest, prioritized self-assessment at the point this
document was written — not exhaustive, but the list actually discussed:

1. **Terraform never actually applied** — validated thoroughly, never run
   for real (`apply`/`destroy`).
2. **CI/CD pipeline never executed** — `azure-pipelines.yml` was authored
   but never run against a live Azure DevOps org; GitHub Actions experience
   is also increasingly expected alongside/instead of Azure Pipelines.
3. **No self-authored OPA/Gatekeeper policy** — every policy encountered
   this session was pre-existing AKS "deployment safeguards"; writing a
   custom constraint template was never done.
4. **No real traffic-splitting** — confirmed via "No TrafficRouting
   Reconcilers found" in the Argo Rollouts logs (§31); canary here is only
   ever replica-count-approximated, never true percentage-based routing via
   a service mesh or Application Gateway for Containers.
5. **Observability maturity** — metrics + logs exist, but no distributed
   tracing (OpenTelemetry), no defined SLO/error-budget practice, no
   Alertmanager routing to a real paging tool.
6. **No DR/backup story** — no Velero, no database backup/restore tested,
   no multi-region design, no chaos engineering, no load testing ever run.
7. **No FinOps practice** — infra was deleted to save cost (the right
   instinct), but no formal Azure Cost Management budgets, spot node
   pools, or VPA/bin-packing exercise.
8. **No AWS/GCP equivalents** — flagged from the very start of the session,
   never revisited.
9. **No KEDA** — only CPU-based HPA was ever exercised; event-driven
   scaling (queue depth, custom metrics) is increasingly asked about.
10. **No platform-engineering tooling** — Backstage, Crossplane, or any
    self-service golden-path pattern.
11. **No real stateful/HA data layer** — the in-cluster SQL Server is
    explicitly scaffolding, never a proper HA/backup-tested setup.
12. **Behavioral/process side** — incident postmortems, on-call practice,
    architecture decision records, mentoring stories — not hands-on-able,
    but worth having 2-3 real examples ready, and this project now supplies
    several genuine ones (the NRG lockdown wall in §13, the two-layer
    Rollout/Gatekeeper incident in §29-30, the leaked-credential incident in
    §33).
