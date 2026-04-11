#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$ROOT_DIR/terraform/environments/dev"

cd "$TF_DIR"

cluster_name="$(terraform output -raw cluster_name 2>/dev/null || true)"
if [[ -n "$cluster_name" ]]; then
  aws eks update-kubeconfig --name "$cluster_name" --region us-east-1 >/dev/null
fi

if kubectl get application todo-app -n argocd >/dev/null 2>&1; then
  kubectl delete application todo-app -n argocd --ignore-not-found
fi

helm uninstall todo-app -n todo-app --ignore-not-found >/dev/null 2>&1 || true
kubectl delete ingress -n todo-app todo-app-public todo-app-monitoring --ignore-not-found || true

echo "Waiting for controller-managed ALBs to disappear..."
for _ in {1..60}; do
  remaining="$(kubectl get ingress -A -o jsonpath='{range .items[*]}{.status.loadBalancer.ingress[0].hostname}{"\n"}{end}' 2>/dev/null | grep -E 'elb\.amazonaws\.com|elb\.[a-z0-9-]+\.amazonaws\.com' || true)"
  if [[ -z "$remaining" ]]; then
    break
  fi
  echo "$remaining"
  sleep 10
done

perl -0pi -e 's/alb_dns_name\s*=\s*"[^"]*"/alb_dns_name = ""/' terraform.tfvars

terraform destroy
