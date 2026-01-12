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

## Configuration and secrets

Config (ConfigMap):

- Each overlay uses configMapGenerator reading an env file:

- $APP_NAME/overlays/$ENV/client-config-$ENV.env etc.

The Deployment loads it via:

- ConfigMap name: ${APP_NAME}-${ENV}-config (matches the template output)

Secrets (Vault via ExternalSecret):

- Each overlay includes an ExternalSecret that creates a Secret consumed by the pod:
  - Secret name: ${APP_NAME}-${ENV}-vault

Vault key path convention:

/${NAMESPACE}/${APP_NAME}-${ENV}

Example:

namespace: hetarchief-v3

app: client

env: int

Vault key: /hetarchief-v3/client-int


## Usage

- edit the app_envfile-tmpl add all your envs

- make sure you have $APP_NAME $SVC_PORT $NAMESPACE $ENV set!

- run make bootsstrap to create the yamls

- run make int , to deploy int (dry run for now)
