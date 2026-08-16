# ecommerce-practice

# docker build -t ecommerce-api:practice ./backend
# docker run -d -p 8084:8080 ecommerce-api:practice
# docker build -t ecommerce-web:practice ./frontend
# docker run -d -p 8085:8080 ecommerce-web:practice
# docker compose up --build


docker build -t acrecommercepoc.azurecr.io/ecommerce-api:1.0.0 ./backend
docker build -t acrecommercepoc.azurecr.io/ecommerce-web:1.0.0 ./frontend
az acr login -n acrecommercepoc
docker push acrecommercepoc.azurecr.io/ecommerce-api:1.0.0
docker push acrecommercepoc.azurecr.io/ecommerce-web:1.0.0


az keyvault secret set --vault-name kv-ecommercepoc-xp --name sa-password --value "EcomPoc2026!Str0ng"
az keyvault secret set --vault-name kv-ecommercepoc-xp --name jwt-key --value "Kj8mN2pQr5vWx9yBzC4dEfGhIjKlMnOp12"
az keyvault secret set --vault-name kv-ecommercepoc-xp --name connection-string --value "Server=sqlserver,1433;Database=ECommerceDb;User Id=sa;Password=EcomPoc2026!Str0ng;TrustServerCertificate=True;"
az aks show -g rg-poc -n pocdevcluster --query "addonProfiles.azureKeyvaultSecretsProvider" -o json
az identity create -g rg-poc -n id-ecommerce-api --location swedencentral
MSYS_NO_PATHCONV=1 az role assignment create --assignee-object-id 4dfae3e1-379d-47ed-9356-e8efffcc4f70 --assignee-principal-type ServicePrincipal --role "Key Vault Secrets User" --scope $(az keyvault show -g rg-poc -n kv-ecommercepoc-xp --query id -o tsv)

<!-- az aks get-credentials --resource-group rg-poc --name pocdevcluster --overwrite-existing
kubectl get nodes -o wide
kubectl create secret generic ecommerce-db-secret --namespace ecommerce --from-literal=sa-password='<a-real-strong-password>' --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic ecommerce-api-secret --namespace ecommerce --from-literal=jwt-key='<a-real-32+-char-random-string>' --from-literal=connection-string='Server=sqlserver,1433;Database=ECommerceDb;User Id=sa;Password=<same-real-strong-password>;TrustServerCertificate=True;' --dry-run=client -o yaml | kubectl apply -f - -->


kubectl apply -k k8s/overlays/prod --dry-run=server
kubectl apply -k k8s/overlays/prod 2>&1

cd "backend/src/ECommerce.Api" && dotnet ef database update --connection "Server=localhost,14331;Database=ECommerceDb;User Id=sa;Password=EcomPoc2026!Str0ng;TrustServerCertificate=True;" 2>&1


helm lint "helm/ecommerce-chart"
helm template ecommerce "helm/ecommerce-chart"
kubectl delete -k k8s/overlays/prod
helm install ecommerce helm/ecommerce-chart
helm upgrade ecommerce helm/ecommerce-chart -n ecommerce

nslookup ecommerce-poc-xp.swedencentral.cloudapp.azure.com


helm repo list

helm install argocd argo/argo-cd -n argocd --create-namespace -f helm/values-argocd.yaml 

kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward service/argocd-server -n argocd 8080:443


kubectl apply -f argocd/project.yaml -f argocd/application.yaml 
kubectl get application ecommerce -n argocd -o wide
kubectl port-forward service/argocd-server -n argocd 8080:443