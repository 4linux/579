#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for bin in terraform gcloud jq; do command -v "$bin" >/dev/null || { echo "Dependencia ausente: $bin" >&2; exit 1; }; done
terraform output -raw okd_project_id >/dev/null || { echo 'Execute terraform apply antes.' >&2; exit 1; }
PROJECT=$(terraform output -raw okd_project_id)
DOMAIN=$(terraform output -raw nip_base_domain)
ZONE_NAME=$(terraform output -raw dns_zone)
INITIAL=$(terraform output -raw initial_project_id)
VMZONE=$(terraform output -raw zone)
REGION=$(terraform output -raw region)
RELEASE=$(terraform output -raw release)
MASTER_TYPE=$(terraform output -raw master_machine_type)
CLUSTER_NAME=$(terraform output -raw cluster_name)
# Este pacote usa a chave temporaria para autenticar o instalador no bastion.
TEMP=$(mktemp); trap 'rm -f "$TEMP"' EXIT
sed -e "s|@@OKD_PROJECT@@|$PROJECT|g" \
    -e "s|@@BASE_DOMAIN@@|$DOMAIN|g" \
    -e "s|@@ZONE_NAME@@|$ZONE_NAME|g" \
    -e "s|@@REGION@@|$REGION|g" \
    -e "s|@@RELEASE@@|$RELEASE|g" \
    -e "s|@@MASTER_TYPE@@|$MASTER_TYPE|g" \
    -e "s|@@CLUSTER_NAME@@|$CLUSTER_NAME|g" \
    scripts/bastion-install.sh > "$TEMP"
gcloud compute scp "$TEMP" bastion-host:/tmp/okd421-install.sh --project="$INITIAL" --zone="$VMZONE" --tunnel-through-iap
gcloud compute ssh bastion-host --project="$INITIAL" --zone="$VMZONE" --tunnel-through-iap --command='sudo bash /tmp/okd421-install.sh'
