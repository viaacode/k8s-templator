IMAGE_NAME ?= $(shell echo "$(FINAL_NAME)" | sed -E 's@[@].*$$@@; s@:[^/]*$$@@')
DRY_RUN    ?= --dry-run=client

APP_NAME   ?= demo
ENV        ?= int              # int | qas | prd
FINAL_NAME ?= $(APP_NAME):latest
NAMESPACE  ?= meemoo-infra
ENVS       := int qas prd
REGISTRY_HOST ?= meeregistrymoo.azurecr.io
export APP_NAME
export ENV
export FINAL_NAME
export NAMESPACE

.PHONY: default bootstrap clean deploy int qas prd

# "make APP_NAME=my-app" → bootstrap
default: bootstrap

debug:
	echo $(IMAGE_NAME)

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
		ENV=$$e envsubst < kustomization-overlay-env-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/kustomization.yaml"; \
	done

	@echo "__adding ExternalSecret manifests__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < externalsecret-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-$$e-externalsecret.yaml"; \
	done

	@echo "__adding app config env files__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < app_envfile-tmpl > "./$(APP_NAME)/overlays/$$e/$(APP_NAME)-config-$$e.env"; \
	done


		@echo "__adding per-env patches (resources + env/component labels + annotations)__"
	@for e in $(ENVS); do \
		ENV=$$e envsubst < patch-$$e-tmpl.yaml > "./$(APP_NAME)/overlays/$$e/patch.yaml"; \
	done

	@echo "__✅ created kustomize structure for $(APP_NAME)__"
	@echo "  - ./$(APP_NAME)/base"
	@echo "  - ./$(APP_NAME)/overlays/{int,qas,prd}"

clean:
	@echo "__🤟 removing $(APP_NAME) dir __"
	@rm -rf "./$(APP_NAME)"
	@echo "__✅ removed $(APP_NAME) dir __"
# Generic deploy uses ENV (int/qas/prd)
deploy:
	@echo "Deploying '$(APP_NAME)' to env '$(ENV)' with image '$(FINAL_NAME)'..."
	cd "./$(APP_NAME)/overlays/$(ENV)" &&  kustomize edit set image "$(FINAL_NAME)=$(REGISTRY_HOST)/$(NAMESPACE)/$(APP_NAME):$(ENV)" && \
  kubectl apply $(DRY_RUN) -k .

undeploy:
	kubectl delete -l app=client  svc,deploy,ing

# Convenience targets; ENV is set here and used in deploy + templates
int: ENV=int
int: deploy

qas: ENV=qas
qas: deploy

prd: ENV=prd
prd: deploy
