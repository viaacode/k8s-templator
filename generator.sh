kubectl create deployment "${APP_NAME}" \
  --image="${FINAL_NAME}" \
  --namespace="${NAMESPACE}" \
  --replicas=0 \
  --port="${SVC_PORT}" \
  --dry-run=client \
  -o go-template \
  --template="$(< app.gotmpl)" \
  | tee ./"${APP_NAME}"/base/"${APP_NAME}".yaml
