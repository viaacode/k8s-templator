# k8s-templator
# new_app — Kubernetes app bootstrap (go-template + kustomize)

This repo bootstraps a basic Kubernetes “web app” skeleton from a few templates:

- Generates **Deployment + Service + Ingress** using a `kubectl create deployment ... --dry-run=client` object rendered through a **Go template** (`app.gotmpl`)
- Creates a **kustomize** structure with:
  - `base/` (app manifests)
  - `overlays/{int,qas,prd}/` (env-specific config + ExternalSecret)
- Uses **External Secrets Operator** (`ExternalSecret`) to pull secrets from Vault.

The goal is to quickly scaffold a new app with sane defaults: health probes, resource limits, envFrom config, etc.

---

## Requirements

- `kubectl`
- `kustomize` (optional; `kubectl apply -k` works with recent kubectl)
- `envsubst` (from `gettext`)
- External Secrets Operator installed in the cluster (for `ExternalSecret`)
- A configured `ClusterSecretStore` named `vault-backend`

---

## Repository layout

Templates and generator:

- `app.gotmpl` — Go template that outputs Deployment/Service/Ingress
- `generator.sh` — runs `kubectl create deployment ... --dry-run=client` and renders `app.gotmpl`
- `kustomization-tmpl.yaml` — base kustomization template
- `kustomization-overlay-env-tmpl.yaml` — overlay kustomization template
- `externalsecret-tmpl.yaml` — ExternalSecret template (Vault path per env)
- `app_envfile-tmpl` — env file template used by configMapGenerator
- `Makefile` — orchestration: bootstrap, deploy, clean

Generated app structure (example `client/`):

