#!/usr/bin/env bash
set -euo pipefail
exec > >(tee -a /var/log/okd421-bootstrap.log) 2>&1
PROJECT='@@OKD_PROJECT@@'
DOMAIN='@@BASE_DOMAIN@@'
REGION='@@REGION@@'
RELEASE='@@RELEASE@@'
ZONE='@@ZONE_NAME@@'
MASTER_TYPE='@@MASTER_TYPE@@'
CLUSTER_NAME='@@CLUSTER_NAME@@'
if [[ -e /opt/okd421/.openshift_install_state.json ]]; then
  echo 'Diretorio de instalacao ja usado. Nao reutilize estado antigo.' >&2; exit 1
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl tar jq dnsutils ca-certificates openssh-client haproxy
# A imagem Debian GCP ja inclui gcloud. Nao reinstalar se presente.
command -v gcloud >/dev/null || { echo 'gcloud CLI ausente' >&2; exit 1; }
# Confirmar a API de releases e a presenca do artefato antes do download.
URL="https://github.com/okd-project/okd/releases/download/$RELEASE"
mkdir -p /opt/okd421 /etc/okd421
chmod 700 /etc/okd421
curl -fL --retry 3 "$URL/openshift-install-linux-$RELEASE.tar.gz" -o /tmp/okd421-installer.tar.gz
tar -xzf /tmp/okd421-installer.tar.gz -C /usr/local/bin openshift-install
curl -fL --retry 3 "$URL/openshift-client-linux-$RELEASE.tar.gz" -o /tmp/okd421-client.tar.gz
tar -xzf /tmp/okd421-client.tar.gz -C /usr/local/bin oc kubectl
# Credenciais: chave temporaria da conta de servico do projeto OKD; nao imprimir nem transmitir a chave.
SA="okd-installer-lab@$PROJECT.iam.gserviceaccount.com"
if [[ ! -s /etc/okd421/installer-key.json ]]; then
  gcloud iam service-accounts keys create /etc/okd421/installer-key.json --iam-account="$SA" --project="$PROJECT"
fi
chmod 600 /etc/okd421/installer-key.json
# Usar autenticacao isolada: evita depender das credenciais da VM ao consultar Cloud DNS.
export CLOUDSDK_CONFIG=/etc/okd421/gcloud
mkdir -p "$CLOUDSDK_CONFIG"
chmod 700 "$CLOUDSDK_CONFIG"
# Chaves de Service Account recem-criadas podem demorar a propagar no Google IAM.
# Reutilizar a chave existente e aguardar propagacao, sem gerar chaves extras.
AUTH_OK=0
for WAIT in 0 10 20 40 60 90; do
  if (( WAIT > 0 )); then
    echo "Aguardando ${WAIT}s antes de tentar autenticar novamente..."
    sleep "$WAIT"
  fi
  if gcloud auth activate-service-account "$SA" \
       --key-file=/etc/okd421/installer-key.json --quiet >/dev/null; then
    AUTH_OK=1
    break
  fi
  echo "Falha temporaria ao ativar a Service Account; verificando novamente..." >&2
done
if (( AUTH_OK != 1 )); then
  echo "ERRO: nao foi possivel autenticar a Service Account apos varias tentativas." >&2
  echo "Verifique se a chave esta ativa, corresponde ao email da conta e nao expirou." >&2
  echo "Nao imprima nem compartilhe o conteudo de installer-key.json." >&2
  exit 1
fi
# Confirma que a credencial consegue emitir token antes de iniciar o instalador.
gcloud auth print-access-token >/dev/null


export GOOGLE_APPLICATION_CREDENTIALS=/etc/okd421/installer-key.json
if [[ ! -s /etc/okd421/id_ed25519 ]]; then
  ssh-keygen -q -t ed25519 -N '' -f /etc/okd421/id_ed25519
fi
cat >/opt/okd421/install-config.yaml <<CONFIG
apiVersion: v1
baseDomain: $DOMAIN
metadata:
  name: $CLUSTER_NAME
credentialsMode: Passthrough
compute:
- name: worker
  replicas: 0
  platform:
    gcp:
      type: e2-standard-2
      osDisk:
        diskType: pd-ssd
        diskSizeGB: 65
controlPlane:
  name: master
  replicas: 1
  platform:
    gcp:
      type: $MASTER_TYPE
      osDisk:
        diskType: pd-ssd
        diskSizeGB: 120
platform:
  gcp:
    projectID: $PROJECT
    region: $REGION
    network: okd-network
    controlPlaneSubnet: master-subnet
    computeSubnet: worker-subnet
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
publish: External
pullSecret: '{"auths":{"fake":{"auth":"aWQ6cGFzcwo="}}}'
CONFIG
printf 'sshKey: %s\n' "$(cat /etc/okd421/id_ed25519.pub)" >>/opt/okd421/install-config.yaml
cp /opt/okd421/install-config.yaml /etc/okd421/install-config-backup.yaml
chmod 600 /etc/okd421/install-config-backup.yaml
# Reproduz a etapa de /etc/hosts do laboratorio original, apenas para o bastion.
cat >/usr/local/sbin/okd421-api-watcher <<'WATCH'
#!/usr/bin/env bash
set -euo pipefail
PROJECT='@@OKD_PROJECT@@'
ZONE='@@ZONE_NAME@@'
MASTER_TYPE='@@MASTER_TYPE@@'
CLUSTER_NAME='@@CLUSTER_NAME@@'
API='api.@@CLUSTER_NAME@@.@@BASE_DOMAIN@@.'
for i in $(seq 1 180); do
  records=$(CLOUDSDK_CONFIG=/etc/okd421/gcloud gcloud dns record-sets list --zone="$ZONE" --project="$PROJECT" --format=json 2>/dev/null || echo '[]')
  ip=$(printf '%s' "$records" | jq -r --arg n "$API" '[.[] | select(.type=="A" and .name==$n) | .rrdatas[]] | first // empty')
  if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    sed -i '/# okd421-api-auto$/d' /etc/hosts
    printf '%s %s # okd421-api-auto\n' "$ip" "${API%.}" >> /etc/hosts
    echo "API no bastion: $ip ${API%.}"
    exit 0
  fi
  sleep 20
done
exit 1
WATCH
sed -i "s|@@OKD_PROJECT@@|$PROJECT|g; s|@@ZONE_NAME@@|$ZONE|g; s|@@BASE_DOMAIN@@|$DOMAIN|g; s|@@CLUSTER_NAME@@|$CLUSTER_NAME|g" /usr/local/sbin/okd421-api-watcher
chmod 700 /usr/local/sbin/okd421-api-watcher
cat >/etc/systemd/system/okd421-api-watcher.service <<'UNIT'
[Unit]
Description=Mapeia API do OKD para /etc/hosts no Bastion
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/okd421-api-watcher
UNIT
printf '[Unit]\nDescription=OKD 4.21 cluster installation\nAfter=network-online.target\nWants=network-online.target\n[Service]\nType=oneshot\nEnvironment=GOOGLE_APPLICATION_CREDENTIALS=/etc/okd421/installer-key.json\nEnvironment=CLOUDSDK_CONFIG=/etc/okd421/gcloud\nExecStart=/usr/local/bin/openshift-install create cluster --dir=/opt/okd421 --log-level=info\nStandardOutput=journal\nStandardError=journal\n[Install]\nWantedBy=multi-user.target\n' >/etc/systemd/system/okd421-install.service

# Configurar HAProxy apenas apos o ingresso receber IP externo.
cat >/usr/local/sbin/okd421-ingress-proxy <<'PROXY'
#!/usr/bin/env bash
set -euo pipefail
PROJECT='@@OKD_PROJECT@@'
DOMAIN='@@BASE_DOMAIN@@'
CLUSTER='@@CLUSTER_NAME@@'
KUBECONFIG=/opt/okd421/auth/kubeconfig
for i in $(seq 1 360); do
  if [[ -s "$KUBECONFIG" ]]; then
    ip=$(/usr/local/bin/oc --kubeconfig="$KUBECONFIG" get svc router-default -n openshift-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      cat >/etc/haproxy/okd421.cfg <<EOF
frontend okd_http
    bind *:80
    mode tcp
    option tcplog
    default_backend okd_http_backend
backend okd_http_backend
    mode tcp
    server okd-router $ip:80 check
frontend okd_https
    bind *:443
    mode tcp
    option tcplog
    default_backend okd_https_backend
backend okd_https_backend
    mode tcp
    server okd-router $ip:443 check
EOF
      # O include isolado evita duplicar blocos ao executar novamente.
      if ! grep -q '^# OKD421 managed proxy$' /etc/haproxy/haproxy.cfg; then
        printf '\n# OKD421 managed proxy\n' >> /etc/haproxy/haproxy.cfg
        cat /etc/haproxy/okd421.cfg >> /etc/haproxy/haproxy.cfg
      else
        sed -i '/^# OKD421 managed proxy$/,$d' /etc/haproxy/haproxy.cfg
        printf '\n# OKD421 managed proxy\n' >> /etc/haproxy/haproxy.cfg
        cat /etc/haproxy/okd421.cfg >> /etc/haproxy/haproxy.cfg
      fi
      haproxy -c -f /etc/haproxy/haproxy.cfg
      systemctl enable --now haproxy
      systemctl reload-or-restart haproxy
      echo "HAProxy: apps.$CLUSTER.$DOMAIN -> $ip:80/443"
      exit 0
    fi
  fi
  sleep 20
done
echo 'Ingress LB nao encontrado (timeout). Use journalctl -u okd421-haproxy.service.' >&2
exit 1
PROXY
sed -i "s|@@OKD_PROJECT@@|$PROJECT|g; s|@@BASE_DOMAIN@@|$DOMAIN|g; s|@@CLUSTER_NAME@@|$CLUSTER_NAME|g" /usr/local/sbin/okd421-ingress-proxy
chmod 700 /usr/local/sbin/okd421-ingress-proxy
cat >/etc/systemd/system/okd421-haproxy.service <<'UNIT'
[Unit]
Description=Descoberta do Ingress OKD e configuracao do HAProxy
After=network-online.target okd421-install.service
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/okd421-ingress-proxy
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable okd421-install.service
systemctl start --no-block okd421-api-watcher.service
systemctl start --no-block okd421-install.service
systemctl enable okd421-haproxy.service
systemctl start --no-block okd421-haproxy.service
echo 'Instalacao iniciada: sudo journalctl -u okd421-install.service -f'
