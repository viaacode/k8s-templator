## ___________________Usage___________________
# Use deploy for you ci app to set image tag
# Use DRY_RUN='' to disable dry run during deploy , use DRY_RUN='-o yaml' to view yamls that are created
#
# --- Global settings --------------------------------------------------------
K8S_CTX ?= kind-kind
# Export these so sub-makefiles can see them
export K8S_CTX
export LOCAL_DOMAIN ?= kind.local

CFG_REPO_URL  ?= https://github.com/viaacode/hetarchief-v3_k8s-resources.git # namespace apps
REPO_URL      ?= https://github.com/viaacode/hetarchief-client.git # code with dockerfile ...
SVC_PORT      ?= 5000
IMAGE_NAME    ?= $(shell echo "$(FINAL_NAME)" | sed -E 's@[@].*$$@@; s@:[^/]*$$@@')
DRY_RUN       ?= --dry-run=client # set optional kubectl options e.g. ='' to disable the dry run  ='-o yaml ' to view rendered yamls 
# defaults
APP_NAME      ?= demo
ENV           ?= int              # int | qas | prd
FINAL_NAME    ?= $(APP_NAME):latest
NAMESPACE     ?= meemoo-infra
ENVS          := int qas prd
REGISTRY_HOST ?= meeregistrymoo.azurecr.io

#CD
ARGOPW        := $(shell $(MAKE) -C /opt/cloudmigration/meePlatFormoo/CiCd/ArgoCD/ get-pass |tail -n2|head -n1)

#PREFIX names

PREFIX        ?= $(NAMESPACE)
SUFFIX        ?= int

## configuration list of NAMESAPCE apps
APPS          := client proxy hasura
# App Metadata: Port and Source Code Repo
client_PORT      := 3000
client_REPO      := $(REPO_URL)
client_CFG_REPO  :=  $(CFG_REPO_URL)
proxy_PORT       := 5000
proxy_REPO       := https://github.com/viaacode/hetarchief-proxy.git
proxy_CFG_REPO   :=  $(CFG_REPO_URL)
hasura_PORT      := 8080
hasura_REPO      := https://github.com/viaacode/hetarchief-hasura.git
hasura_CFG_REPO  :=  $(CFG_REPO_URL)


.PHONY: set-ns build-all deploy-all-envs redeploy-all-envs undeploy-all-apps
set-ns:
	@kubectl config use-context $(K8S_CTX)
	@kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl config set-context --current --namespace=$(NAMESPACE)

# Example: Run your templator and kustomize build for every app
build-all: set-ns
	@$(foreach app, $(APPS), \
		echo "--- Processing $(app) ---"; \
		APP_NAME=$(app) \
		SVC_PORT=$($(app)_PORT) \
		REPO_URL=$($(app)_REPO) \
		SUFFIX=$${ENV} \
		$(MAKE) bootstrap; \
		$(MAKE) deploy-all-envs APP_NAME=$(app) SVC_PORT=$($(app)_PORT) REPO_URL=$($(app)_CFG_REPO); \
	)
	$(MAKE) deploy-all-envs
	$(MAKE) create_structure
	$(MAKE) generate-argocd
	@echo "All resources generated in k8s-resources/"
	tree k8s-resources

# Helper to run deploy for all envs this sets the tag to $ENV
deploy-all-envs: set-ns
	@for e in $(ENVS); do \
		ENV=$$e $(MAKE) deploy; \
	done

redeploy-all-envs: set-ns
	@for e in $(ENVS); do \
                ENV=$$e $(MAKE) redeploy; \
        done

undeploy-all-apps: set-ns
	@for e in $(APPS); do \
                APP_NAME=$$e $(MAKE) undeploy; \
        done

.PHONY: generate-argocd argocd-deploy
# This target generates the ArgoCD manifests for each app/env
generate-argocd:
	@echo "__creating ArgoCD manifests__"
	@mkdir -p k8s-resources/argocd/int k8s-resources/argocd/qas k8s-resources/argocd/prd
	@$(foreach env, $(ENVS), \
		ENV=$(env) envsubst < argocd-root-tmpl.yaml > k8s-resources/argocd/$(env)/root-app.yaml; \
		$(foreach app, $(APPS), \
			APP_NAME=$(app) ENV=$(env) envsubst < argocd-child-tmpl.yaml > k8s-resources/argocd/$(env)/$(app)-$(env).yaml; \
		) \
	)

argocd-deploy-root-env: set-ns
	 kubectl apply -f k8s-resources/argocd/$(ENV)/root-app.yaml

create_structure:
	  @$(foreach app, $(APPS), \
                echo "Building $(app)..."; \
                mv $(app) k8s-resources/kustomize/$(app); \
        )
push:
	git add k8s-resources/
	git commit -m "Deploying $(NAMESAPCE) stack: $(APPS)"
	git push origin main


export APP_NAME ENV FINAL_NAME NAMESPACE PREFIX SUFFIX CFG_REPO_URL

.PHONY: default bootstrap clean deploy int qas prd

# "make APP_NAME=my-app" → bootstrap
default: bootstrap

debug:
	echo $(IMAGE_NAME)
lint:
	kustomize build "k8s-resources/kustomize/$(APP_NAME)/overlays/$(ENV)" >/dev/null

bootstrap:
	@echo "Bootstrapping app '$(APP_NAME)' with image '$(FINAL_NAME)' in namespace '$(NAMESPACE)'..."
	@mkdir -p "./$(APP_NAME)/base"
	@for e in $(ENVS); do \
		mkdir -p "./$(APP_NAME)/overlays/$$e"; \
	done

	@echo "__running generator.sh__"
	@./generator.sh

	@echo "__creating base kustomization__"
	@envsubst < kustomization-tmpl.yaml > "./$(APP_NAME)/base/kustomization.yaml"

	@echo "__creating overlay kustomizations (int/qas/prd)__"
	@for e in $(ENVS); do \
		SUFFIX=$$e ENV=$$e envsubst < kustomization-overlay-env-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/kustomization.yaml"; \
	done

	@echo "__adding ExternalSecret manifests__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < externalsecret-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-$$e-externalsecret.yaml"; \
	done

	@echo "__adding app config env files__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < app_envfile-tmpl > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-config-$$e.env"; \
	done
	# Edit this to set limits and replicas
	@for e in $(ENVS); do \
		case $$e in \
		  int) REPLICAS=0 CPU_REQUEST=50m  MEM_REQUEST=64Mi  CPU_LIMIT=200m MEM_LIMIT=256Mi ;; \
		  qas) REPLICAS=1 CPU_REQUEST=100m MEM_REQUEST=128Mi CPU_LIMIT=250m MEM_LIMIT=384Mi ;; \
		  prd) REPLICAS=2 CPU_REQUEST=200m MEM_REQUEST=256Mi CPU_LIMIT=200m MEM_LIMIT=256Mi ;; \
		esac; \
		ENV=$$e REPLICAS=$$REPLICAS envsubst < patch-replicas-tmpl.yaml  > "./$(APP_NAME)/overlays/$$e/patch-replicas.yaml"; \
		ENV=$$e CPU_REQUEST=$$CPU_REQUEST MEM_REQUEST=$$MEM_REQUEST CPU_LIMIT=$$CPU_LIMIT MEM_LIMIT=$$MEM_LIMIT \
		  envsubst < patch-resources-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/patch-resources.yaml"; \
	done

	@echo "__✅ created kustomize structure for $(APP_NAME)__"
	@echo "  - ./$(APP_NAME)/base"
	@echo "  - ./$(APP_NAME)/overlays/{int,qas,prd}"

clean:
	@echo "__🤟 removing $(APPS) dir __"
	rm -rf $(APPS)
	@echo "__✅ removed $(APPS) dir __"
	@$(foreach app, $(APPS), \
                echo "__🤟 Deletinging $(app)..."; \
                rm -rf k8s-resources/kustomize/$(app); \
        )

	@$(foreach e, $(ENVS), \
		rm -rf k8s-resources/argocd/$$e/*; \
	)
	@echo "__✅ removed $(APPS) dirs from k8s-resources/kustomize __"


# Generic deploy uses ENV (int/qas/prd)
deploy:
	@echo "Deploying '$(APP_NAME)' to env '$(ENV)' with image '$(FINAL_NAME)'..."
	cd "./$(APP_NAME)/overlays/$(ENV)" &&  kustomize edit set image "$(FINAL_NAME)=$(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)" && \
  kubectl apply $(DRY_RUN) -k .

redeploy: set-ns
	@echo "Deploying '$(APP_NAME)' to env '$(ENV)' with image '$(FINAL_NAME)'..."
	cd "k8s-resources/$(APP_NAME)/overlays/$(ENV)" && \
  kustomize edit set image "$(FINAL_NAME)=$(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)" && \
  kubectl apply $(DRY_RUN) -k .

undeploy: set-ns
	kubectl delete -l app=$(APP_NAME)  svc,deploy,ing

# Convenience targets; ENV is set here and used in deploy + templates
## K8S_CTX is important each env is in other cluster so set context !
int: ENV=int
int: K8S_CTX=kind-kind
int: set-ns build-all lint argocd-deploy-root-env

qas: ENV=qas
qas: K8S_CTX=aks-tst
qas: set-ns clean build-all lint argocd-deploy-root-env

prd: ENV=prd
prd: set-ns build-all lint argocd-deploy-root-env


argocd_login: set-ns
	bash -c 'argocd login --core'
test_argocd: set-ns
	@argocd app list
