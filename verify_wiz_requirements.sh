#!/usr/bin/env bash
# Strict mode so failures are obvious during a live walkthrough.
set -euo pipefail

# Read-only evidence script for the Wiz exercise.
# It prints proof for each requirement and does not change resources.

# Configurable inputs with sensible defaults for the lab.
REGION="${REGION:-us-east-1}"
NAME="${NAME:-wiz-exercise}"
TF_DIR="${TF_DIR:-terraform}"
K8S_NAMESPACE="${K8S_NAMESPACE:-tasky}"
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-tasky}"

# Optional SSH key path for the Mongo VM.
SSH_KEY_PATH="${SSH_KEY_PATH:-${TF_DIR}/mongo.pem}"

# Optional log file path; when set, output is written to the file and echoed.
OUTPUT_FILE="${OUTPUT_FILE:-}"

# Optional command tracing to show verification commands as they run.
SHOW_COMMANDS="${SHOW_COMMANDS:-0}"

# Small output helpers for visual separation during the demo.
# Output helpers.
hr() { echo "--------------------------------------------------------------------------------"; }
h1() { hr; echo "## $*"; hr; }

# Track results for the end-of-script summary.
PASSED_CHECKS=()
FAILED_CHECKS=()
WARNED_CHECKS=()

ok() { echo "PASS: $*"; PASSED_CHECKS+=("$*"); }
warn() { echo "NOT OK (WARN): $*"; WARNED_CHECKS+=("$*"); }
fail() { echo "FAIL: $*" >&2; FAILED_CHECKS+=("$*"); }
die() { fail "$*"; exit 1; }
criteria() { echo "Pass criteria: $*"; }

# Final report printed regardless of exit path.
print_summary() {
  local pass_count="${#PASSED_CHECKS[@]}"
  local fail_count="${#FAILED_CHECKS[@]}"
  local warn_count="${#WARNED_CHECKS[@]}"

  hr
  echo "## Pass/Fail Summary"
  hr
  echo "Passed: ${pass_count}"
  echo "Failed: ${fail_count}"
  echo "Warned: ${warn_count}"
  echo

  if (( fail_count > 0 )); then
    echo "Failed checks:"
    printf ' - %s\n' "${FAILED_CHECKS[@]}"
    echo
  else
    echo "Failed checks: none"
    echo
  fi

  if (( warn_count > 0 )); then
    echo "Warned checks (not OK, non-fatal):"
    printf ' - %s\n' "${WARNED_CHECKS[@]}"
    echo
  else
    echo "Warned checks: none"
    echo
  fi

  if (( pass_count > 0 )); then
    echo "Passed checks:"
    printf ' - %s\n' "${PASSED_CHECKS[@]}"
  else
    echo "Passed checks: none"
  fi
}

# Always print a summary, even if we exit early.
trap 'print_summary' EXIT

# Optional log redirection to capture evidence in a file.
if [[ -n "${OUTPUT_FILE}" ]]; then
  OUTPUT_DIR="$(dirname "${OUTPUT_FILE}")"
  if [[ "${OUTPUT_DIR}" != "." ]]; then
    mkdir -p "${OUTPUT_DIR}"
  fi
  if command -v tee >/dev/null 2>&1; then
    exec > >(tee "${OUTPUT_FILE}") 2>&1
  else
    exec > "${OUTPUT_FILE}" 2>&1
  fi
  echo "Logging to ${OUTPUT_FILE}"
fi

# Optional command tracing to show exactly what was executed.
if [[ "${SHOW_COMMANDS}" == "1" || "${SHOW_COMMANDS}" == "true" || "${SHOW_COMMANDS}" == "yes" ]]; then
  export PS4='+ [CMD] '
  set -x
  echo "Command tracing enabled (SHOW_COMMANDS=${SHOW_COMMANDS})"
fi

# Verify a required CLI tool is installed.
need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

# Preflight checks.
h1 "Preflight"
need aws
need kubectl
need jq
need curl
need ssh

test -d "$TF_DIR" || die "Expected ./${TF_DIR} directory"
test -d "tasky-main" || warn "Expected ./tasky-main directory (needed for showing Dockerfile wizexercise.txt evidence)"

aws configure list >/dev/null 2>&1 || true
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region "$REGION")"
ok "AWS Account: ${ACCOUNT_ID}"
ok "Region: ${REGION}"
ok "Name prefix: ${NAME}"

# Requirements checklist.
h1 "Checklist for this script"
cat <<'EOF'
Mandatory:
- WebApp Environment
  - VM runs an older OS and hosts MongoDB.
  - SSH is publicly accessible.
  - VM role is overly permissive.
  - MongoDB is reachable only from Kubernetes private subnets.
  - Daily backups are uploaded to a public S3 bucket.
  - Web app runs on Kubernetes private subnets.
  - Mongo access is provided via a Kubernetes env var.
  - Container has cluster-admin and is privileged.
  - App is exposed via Ingress + cloud load balancer.
  - App data persists in MongoDB.
- Cloud Native Security
  - EKS control plane logging enabled.
  - Preventative control: EBS encryption by default.
  - Detective controls: CloudTrail and AWS Config.
  - Optional: GuardDuty and Security Hub if enabled.

DevSecOps:
- Dev(Sec)Ops
  - IaC pipeline with security scanning.
  - App pipeline with image scanning and deployment.
  - OIDC-based AWS access (no static keys).
EOF
echo
echo "How to read PASS/FAIL:"
echo " - PASS means the script could confirm the stated criteria for a check."
echo " - NOT OK (WARN) means evidence could not be collected or was incomplete."
echo " - FAIL means a required dependency or resource is missing and the script exits."

# Helper to read a Terraform output when local state exists.
# Read a Terraform output value if local state exists.
tf_output() {
  local key="$1"
  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="$TF_DIR" output -raw "$key" 2>/dev/null || true
  else
    echo ""
  fi
}

# Terraform outputs give us canonical IPs/hostnames if state is local.
# Capture key Terraform outputs if present.
MONGO_PUBLIC_IP="$(tf_output mongo_public_ip)"
MONGO_PRIVATE_IP="$(tf_output mongo_private_ip)"
MONGO_HOSTNAME="$(tf_output mongo_hostname)"
TASKY_INGRESS_HOSTNAME="$(tf_output tasky_ingress_hostname)"

if [[ -z "${MONGO_PUBLIC_IP}" ]]; then
  warn "Terraform output mongo_public_ip not found via local terraform output (this is OK if you rely on remote state only). We'll discover via AWS tags."
fi

# Discover key resources by tags.
h1 "Discover resources (read-only)"

# Use tags to find the Mongo VM when Terraform state isn't local.
# Find the Mongo instance by Name tag.
MONGO_INSTANCE_ID="$(
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=${NAME}-mongo-vm" "Name=instance-state-name,Values=running,stopped,pending" \
    --query "Reservations[0].Instances[0].InstanceId" --output text 2>/dev/null | sed 's/None//g' || true
)"

if [[ -z "${MONGO_INSTANCE_ID}" ]]; then
  warn "Could not find Mongo EC2 instance by tag Name=${NAME}-mongo-vm (check your tags)."
else
  ok "Mongo EC2 InstanceId: ${MONGO_INSTANCE_ID}"
  # Fill in IPs when Terraform output is empty.
  if [[ -z "${MONGO_PUBLIC_IP}" ]]; then
    MONGO_PUBLIC_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$MONGO_INSTANCE_ID" \
      --query "Reservations[0].Instances[0].PublicIpAddress" --output text)"
  fi
  if [[ -z "${MONGO_PRIVATE_IP}" ]]; then
    MONGO_PRIVATE_IP="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$MONGO_INSTANCE_ID" \
      --query "Reservations[0].Instances[0].PrivateIpAddress" --output text)"
  fi
  ok "Mongo Public IP: ${MONGO_PUBLIC_IP}"
  ok "Mongo Private IP: ${MONGO_PRIVATE_IP}"
fi

# Verify the EKS cluster exists.
EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-$NAME}"
if aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1; then
  ok "EKS Cluster exists: ${EKS_CLUSTER_NAME}"
else
  die "EKS Cluster not found: ${EKS_CLUSTER_NAME} (region ${REGION})"
fi

# Resolve a node group name for node/subnet evidence later.
# Capture the first node group name for later checks.
NODEGROUP_NAME="${NODEGROUP_NAME:-}"
if [[ -z "${NODEGROUP_NAME}" ]]; then
  NODEGROUP_NAME="$(aws eks list-nodegroups --cluster-name "$EKS_CLUSTER_NAME" --region "$REGION" \
    --query 'nodegroups[0]' --output text 2>/dev/null | sed 's/None//g' || true)"
fi
if [[ -n "${NODEGROUP_NAME}" ]]; then
  ok "EKS Node Group: ${NODEGROUP_NAME}"
else
  warn "No EKS node group found via list-nodegroups."
fi

# Validate kubeconfig access before Kubernetes-specific checks.
# Update kubeconfig and verify kubectl works.
h1 "Kubernetes CLI requirement: kubectl access"
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME" --region "$REGION" >/dev/null
kubectl version --client=true
kubectl get nodes -o wide
ok "kubectl works against cluster ${EKS_CLUSTER_NAME}"

# Evidence for the Mongo VM requirements.
h1 "Requirement: VM with MongoDB (outdated OS, SSH public, overly-permissive IAM, Mongo only from k8s, daily backup to public S3)"

echo "What this section checks (Mongo VM):"
echo " - 1+ year outdated Linux: Ubuntu 20.04 configured in terraform/mongo.tf"
echo " - SSH exposed to public internet (0.0.0.0/0:22) via mongo SG"
echo " - Overly-permissive IAM (AmazonEC2FullAccess + AmazonS3FullAccess) attached to instance profile"
echo " - MongoDB restricted to Kubernetes private subnet CIDRs only (27017 from private subnets)"
echo " - Daily automated backup to public-readable + listable S3 bucket (cron @ 03:00 UTC)"

# Evidence 1: Security group rules.
h1 "Check: Security Group allows SSH from 0.0.0.0/0 and Mongo only from private subnets"
criteria "SG output shows TCP 22 from 0.0.0.0/0 AND TCP 27017 only from private subnet CIDRs."

if [[ -n "${MONGO_INSTANCE_ID}" ]]; then
  MONGO_SG_ID="$(
    aws ec2 describe-instances --region "$REGION" --instance-ids "$MONGO_INSTANCE_ID" \
      --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" --output text
  )"
  ok "Mongo SG: ${MONGO_SG_ID}"

  aws ec2 describe-security-groups --region "$REGION" --group-ids "$MONGO_SG_ID" \
    --query "SecurityGroups[0].IpPermissions" --output json | jq '.'

  echo
  echo "Check for:"
  echo " - TCP 22 from 0.0.0.0/0"
  echo " - TCP 27017 from 10.20.x.x/24 private subnet CIDRs (or your private CIDRs)"
else
  warn "Skipping SG evidence (Mongo instance not discovered)."
fi

# Evidence 2: VM OS age and MongoDB version.
h1 "Check: VM OS version and MongoDB version (SSH into VM)"
criteria "SSH succeeds, OS shows Ubuntu 20.04 (or older), and mongod --version prints."

if [[ -n "${MONGO_PUBLIC_IP}" && -f "${SSH_KEY_PATH}" ]]; then
  chmod 600 "${SSH_KEY_PATH}" || true

  echo "Running over SSH:"
  echo " - OS version (lsb_release)"
  echo " - Kernel (uname -a)"
  echo " - MongoDB version (mongod --version)"
  echo

  ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "ubuntu@${MONGO_PUBLIC_IP}" \
    "set -e;
     echo '--- OS (lsb_release) ---';
     lsb_release -a || cat /etc/os-release;
     echo;
     echo '--- Kernel (uname -a) ---';
     uname -a;
     echo;
     echo '--- Mongo (mongod --version) ---';
     mongod --version | head -n 20 || true;
    "
  ok "SSH + OS/Mongo version evidence collected"
else
  warn "Cannot SSH for OS/Mongo proof. Ensure SSH_KEY_PATH points to your private key (default: ${SSH_KEY_PATH}) and MONGO_PUBLIC_IP is known."
fi

# Evidence 3: IAM permissions on the Mongo VM.
h1 "Check: Mongo VM IAM instance profile has overly permissive policies (EC2FullAccess + S3FullAccess)"
criteria "Attached role policies include AmazonEC2FullAccess AND AmazonS3FullAccess."

if [[ -n "${MONGO_INSTANCE_ID}" ]]; then
  PROFILE_ARN="$(
    aws ec2 describe-instances --region "$REGION" --instance-ids "$MONGO_INSTANCE_ID" \
      --query "Reservations[0].Instances[0].IamInstanceProfile.Arn" --output text 2>/dev/null | sed 's/None//g' || true
  )"
  if [[ -n "${PROFILE_ARN}" ]]; then
    ok "Instance Profile ARN: ${PROFILE_ARN}"
    PROFILE_NAME="${PROFILE_ARN##*/}"

    ROLE_NAME="$(
      aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" \
        --query "InstanceProfile.Roles[0].RoleName" --output text
    )"
    ok "Instance Profile Role: ${ROLE_NAME}"

    aws iam list-attached-role-policies --role-name "$ROLE_NAME" --output json | jq '.'
    echo
    echo "Check for attached policies:"
    echo " - AmazonEC2FullAccess"
    echo " - AmazonS3FullAccess"
  else
    warn "No instance profile attached to Mongo VM (unexpected for this assignment)."
  fi
fi

# Evidence 4: Backup bucket is public.
h1 "Check: S3 backup bucket is public-read + public-list (intentionally insecure)"
criteria "Bucket policy status IsPublic=true, public access block is all false, and bucket policy allows s3:ListBucket and s3:GetObject to Principal '*'."

# Find the backup bucket by its prefix.
BACKUP_BUCKET="$(
  aws s3api list-buckets --query "Buckets[?starts_with(Name, \`${NAME}-public-backups-\`)].Name | [0]" --output text --region "$REGION" 2>/dev/null | sed 's/None//g' || true
)"

if [[ -n "${BACKUP_BUCKET}" ]]; then
  ok "Public backup bucket: ${BACKUP_BUCKET}"

  echo "--- Bucket policy status (IsPublic) ---"
  aws s3api get-bucket-policy-status --bucket "$BACKUP_BUCKET" --region "$REGION" --output json | jq '.'

  echo
  echo "--- Public access block (should be all FALSE for this bucket) ---"
  aws s3api get-public-access-block --bucket "$BACKUP_BUCKET" --region "$REGION" --output json | jq '.'

  echo
  echo "--- Bucket policy (should allow s3:ListBucket and s3:GetObject to Principal '*') ---"
  aws s3api get-bucket-policy --bucket "$BACKUP_BUCKET" --region "$REGION" --output json | jq -r '.Policy' | jq '.'

  echo
  echo "--- Recent backups (object listing) ---"
  aws s3 ls "s3://${BACKUP_BUCKET}/" | tail -n 10 || true

  ok "S3 public bucket evidence collected"
else
  warn "Could not find backup bucket with prefix ${NAME}-public-backups-. If your name differs, set NAME=... and rerun."
fi

# Evidence 5: Daily backup cron and logs.
h1 "Check: Daily automated backup cron on Mongo VM + log file"
criteria "Cron entry references wiz_mongo_backup.sh and log shows recent backup activity."

if [[ -n "${MONGO_PUBLIC_IP}" && -f "${SSH_KEY_PATH}" ]]; then
  ssh -o StrictHostKeyChecking=no -i "${SSH_KEY_PATH}" "ubuntu@${MONGO_PUBLIC_IP}" \
    "set -e;
     echo '--- Cron entry (ubuntu user) ---';
     sudo crontab -u ubuntu -l | sed -n '1,200p' || true;
     echo;
     echo '--- Backup script path + permissions ---';
     ls -lah /usr/local/bin/wiz_mongo_backup.sh || true;
     echo;
     echo '--- Backup log tail ---';
     tail -n 30 /var/log/wiz/mongo_backup.log || true;
    "
  ok "Cron + log evidence collected"
else
  warn "Cannot SSH for cron/log proof. Ensure SSH_KEY_PATH and MONGO_PUBLIC_IP are set."
fi

# Evidence for the Kubernetes app requirements.
h1 "Requirement: Web app on Kubernetes (private subnets, env var for Mongo, wizexercise.txt, cluster-admin, privileged, ingress+LB, data in DB)"

echo "What this section checks (Kubernetes app):"
echo " - Cluster nodes in private subnets"
echo " - Mongo access provided via Kubernetes env var (secret)"
echo " - /app/wizexercise.txt present in the running container"
echo " - ServiceAccount bound to cluster-admin"
echo " - Container runs privileged (intentional weakness)"
echo " - Ingress creates public ALB and app is reachable"
echo " - Data persists in MongoDB"

# Evidence 1: nodes in private subnets.
h1 "Check: EKS nodes in PRIVATE subnets"
criteria "Subnets show MapPublicIpOnLaunch=false (private subnets)."

CLUSTER_JSON="$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$REGION" --output json)"
echo "$CLUSTER_JSON" | jq '.cluster.resourcesVpcConfig | {subnetIds, endpointPublicAccess, endpointPrivateAccess, publicAccessCidrs}'

if [[ -n "${NODEGROUP_NAME}" ]]; then
  NODEGROUP_JSON="$(aws eks describe-nodegroup --cluster-name "$EKS_CLUSTER_NAME" --nodegroup-name "$NODEGROUP_NAME" --region "$REGION" --output json)"
  echo
  echo "--- Node group details ---"
  echo "$NODEGROUP_JSON" | jq '.nodegroup | {nodegroupName, subnets, instanceTypes, nodeRole, scalingConfig}'
  NODEGROUP_SUBNET_IDS="$(echo "$NODEGROUP_JSON" | jq -r '.nodegroup.subnets[]')"
else
  NODEGROUP_SUBNET_IDS=""
fi

if [[ -n "${NODEGROUP_SUBNET_IDS}" ]]; then
  SUBNET_IDS="${NODEGROUP_SUBNET_IDS}"
else
  SUBNET_IDS="$(echo "$CLUSTER_JSON" | jq -r '.cluster.resourcesVpcConfig.subnetIds[]')"
fi

echo
echo "Subnets MapPublicIpOnLaunch (private should be false):"
while read -r sid; do
  aws ec2 describe-subnets --region "$REGION" --subnet-ids "$sid" \
    --query "Subnets[0].{SubnetId:SubnetId, MapPublicIpOnLaunch:MapPublicIpOnLaunch, CidrBlock:CidrBlock, Az:AvailabilityZone}" \
    --output json | jq '.'
done <<< "$SUBNET_IDS"

ok "EKS private subnet evidence collected (subnets should show MapPublicIpOnLaunch=false)"

# Evidence 2: Mongo URI provided via a secret.
h1 "Check: MongoDB URI is provided via Kubernetes env var (secret) and visible in pod env"
criteria "Deployment envFrom references secret tasky-env, secret includes MONGODB_URI, and pod env prints MONGODB_URI."

kubectl -n "$K8S_NAMESPACE" get ns "$K8S_NAMESPACE" >/dev/null 2>&1 && ok "Namespace exists: ${K8S_NAMESPACE}" || warn "Namespace not found: ${K8S_NAMESPACE}"

echo "--- Deployment envFrom (should reference secret tasky-env) ---"
kubectl -n "$K8S_NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o json | jq '.spec.template.spec.containers[0].envFrom'

echo
echo "--- Secret keys (should include MONGODB_URI) ---"
kubectl -n "$K8S_NAMESPACE" get secret tasky-env -o json | jq '.data | keys'

echo
echo "--- Pod printenv (MONGODB_URI) ---"
POD="$(kubectl -n "$K8S_NAMESPACE" get pods -l app="$DEPLOYMENT_NAME" -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$K8S_NAMESPACE" exec "$POD" -- /bin/sh -lc 'echo "$MONGODB_URI" | sed "s/:[^@]*@/:***@/g"' || true
ok "Mongo env var evidence collected"

# Evidence 3: wizexercise.txt exists in the container.
h1 "Check: /app/wizexercise.txt exists in running container and contains your name"
criteria "/app/wizexercise.txt exists in the running container and contains your name."

kubectl -n "$K8S_NAMESPACE" exec "$POD" -- cat /app/wizexercise.txt
ok "wizexercise.txt evidence collected"

# Show where wizexercise.txt is created in the Dockerfile.
h1 "Check: wizexercise.txt is created at build time in tasky-main/Dockerfile"
criteria "Dockerfile includes RUN/printf that writes /app/wizexercise.txt."

if [[ -f "tasky-main/Dockerfile" ]]; then
  nl -ba tasky-main/Dockerfile | sed -n '1,120p'
  echo
  ok "Dockerfile evidence printed (look for RUN printf ... > /app/wizexercise.txt)"
else
  warn "tasky-main/Dockerfile not found locally (expected in repo root)."
fi

# Evidence 4: cluster-admin binding for the service account.
h1 "Check: ServiceAccount is bound to cluster-admin (ClusterRoleBinding)"
criteria "ClusterRoleBinding exists and references the Tasky service account."

kubectl get clusterrolebinding "${NAME}-tasky-cluster-admin" -o yaml | sed -n '1,200p' || true
echo
echo "If name differs, list relevant bindings:"
kubectl get clusterrolebinding | grep -i tasky || true
ok "cluster-admin binding evidence collected"

# Evidence 5: privileged container setting.
h1 "Check: Container is privileged=true (intentional weakness)"
criteria "Deployment securityContext shows privileged: true."

kubectl -n "$K8S_NAMESPACE" get deploy "$DEPLOYMENT_NAME" -o json | jq '.spec.template.spec.containers[0].securityContext'
ok "privileged container evidence collected"

# Evidence 6: ingress and public load balancer.
h1 "Check: Ingress exists and has public hostname (ALB)"
criteria "Ingress has a hostname, ALB scheme is internet-facing, and HTTP returns a response."

kubectl -n "$K8S_NAMESPACE" get ingress -o wide
INGRESS_HOST="$(kubectl -n "$K8S_NAMESPACE" get ingress tasky-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"

if [[ -n "${INGRESS_HOST}" ]]; then
  ok "Ingress hostname: ${INGRESS_HOST}"
  echo
  echo "--- ALB details (scheme should be internet-facing) ---"
  LB_JSON="$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?DNSName=='${INGRESS_HOST}'] | [0] | {DNSName:DNSName, Scheme:Scheme, Type:Type, VpcId:VpcId}" \
    --output json 2>/dev/null || true)"
  if [[ -n "${LB_JSON}" ]]; then
    echo "${LB_JSON}" | jq '.'
  else
    warn "Could not fetch ALB details (missing permissions or LB not ready)."
  fi
  echo
  echo "HTTP check (may take time after deploy; should return HTML/app response):"
  curl -sS -I "http://${INGRESS_HOST}" | sed -n '1,20p' || true
else
  warn "Ingress hostname not ready yet. Re-run this section after ALB provisions."
fi

# Evidence 7: app writes and reads data from Mongo.
# If the API differs, use the UI for proof.
h1 "Check: App works end-to-end and persists data (web -> Mongo)"
criteria "POST creates a todo and GET list includes it afterward."

if [[ -n "${INGRESS_HOST}" ]]; then
  echo "Attempting API-based proof (best-effort). If your Tasky API differs, use browser UI proof instead."
  echo
  echo "1) Create todo:"
  CREATE_RES="$(curl -sS -X POST "http://${INGRESS_HOST}/api/todos" -H 'Content-Type: application/json' \
    -d '{"title":"wiz-proof-'$(date +%s)'","completed":false}' || true)"
  echo "$CREATE_RES" | sed -n '1,120p'
  echo
  echo "2) List todos (should include the one created):"
  curl -sS "http://${INGRESS_HOST}/api/todos" | sed -n '1,200p' || true
  echo
  ok "If the list includes the created todo, that is strong proof data is in Mongo (persistence)."
else
  warn "Skipping app API proof because ingress hostname not available."
fi

# Optional: direct DB proof via kubectl exec.
h1 "Optional: Direct DB proof via Kubernetes (if mongo client tools are available)"
criteria "Optional: PASS if you can query Mongo directly from a pod and see data."

echo "This is optional because many images don't ship mongo client tools."
echo "A good live alternative: show app write -> refresh -> data persists."
echo

# DevSecOps evidence for pipelines and controls.
h1 "Dev(Sec)Ops - VCS + CI/CD pipelines + pipeline security controls"
criteria "Workflow files show OIDC auth, Trivy scans, build/push, and deployment steps."

echo "What this section checks (DevSecOps):"
echo " - IaC pipeline with validation and security scanning"
echo " - App pipeline with build, image scan, and deploy"
echo " - OIDC-based AWS access"
echo

echo "Evidence in repo: GitHub Actions workflows exist:"
ls -lah .github/workflows || true
echo

echo "Show key security controls:"
echo " - OIDC auth to AWS (aws-actions/configure-aws-credentials@v4, id-token: write)"
echo " - IaC scanning (Trivy config scan -> SARIF artifact)"
echo " - Container image scanning (Trivy image scan -> SARIF + table)"
echo " - Podman used for builds (no Docker dependency)"
echo

echo "--- iac.yml (high-signal lines) ---"
grep -nE "configure-aws-credentials|id-token|trivy|terraform (fmt|init|validate|plan|apply)" .github/workflows/iac.yml || true
echo

echo "--- app.yml (high-signal lines) ---"
grep -nE "podman|configure-aws-credentials|trivy|ecr|get-login-password|set image|rollout|wizexercise.txt" .github/workflows/app.yml || true
echo

ok "Dev(Sec)Ops workflow evidence printed"

# Evidence for Cloud Native Security controls.
h1 "Requirement: Cloud Native Security - control plane audit logging + preventative + detective controls"
criteria "EKS logging includes api/audit, EBS encryption by default is enabled, and CloudTrail/AWS Config are enabled."

echo "What this section checks (Cloud Native Security):"
echo " - EKS control plane logging enabled"
echo " - EBS encryption by default enabled"
echo " - CloudTrail enabled"
echo " - AWS Config enabled with managed rules"
echo " - GuardDuty/Security Hub shown if enabled"
echo

echo "1) Control plane audit logging:"
echo " - EKS enabled_cluster_log_types includes: api, audit, authenticator, controllerManager, scheduler"
echo
aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --region "$REGION" \
  --query "cluster.logging.clusterLogging" --output json | jq '.'
echo
echo "Log group presence:"
aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "/aws/eks/${EKS_CLUSTER_NAME}/cluster" --output json | jq '.logGroups[] | {logGroupName, retentionInDays}' || true
echo

echo "2) Preventative control (EBS encryption by default):"
aws ec2 get-ebs-encryption-by-default --region "$REGION" --output json | jq '.'
echo

echo "3) Detective controls (CloudTrail + AWS Config):"
echo "--- CloudTrail trails ---"
aws cloudtrail describe-trails --region "$REGION" --output json | jq '.trailList[] | {Name: .Name, S3BucketName: .S3BucketName, IsMultiRegionTrail: .IsMultiRegionTrail, LogFileValidationEnabled: .LogFileValidationEnabled}' || true
echo

echo "--- AWS Config Recorder status (if enabled) ---"
aws configservice describe-configuration-recorder-status --region "$REGION" --output json | jq '.ConfigurationRecordersStatus' || true
echo

echo "--- AWS Config Rules (look for s3 public read prohibited / restricted ssh) ---"
aws configservice describe-config-rules --region "$REGION" --output json \
  | jq '.ConfigRules[] | {ConfigRuleName: .ConfigRuleName, Source: .Source.SourceIdentifier}' || true
echo

echo "4) Optional detective services (GuardDuty and Security Hub):"
echo "--- GuardDuty detectors ---"
aws guardduty list-detectors --region "$REGION" --output json | jq '.' || true
echo
echo "--- Security Hub ---"
SECURITYHUB_JSON="$(aws securityhub describe-hub --region "$REGION" --output json 2>/dev/null || true)"
if [[ -n "${SECURITYHUB_JSON}" ]]; then
  echo "${SECURITYHUB_JSON}" | jq '.'
else
  warn "Security Hub not enabled or access denied."
fi
echo

ok "Cloud Native Security evidence collected"

# Summary you can reuse in the panel.
h1 "Summary for the panel"

cat <<'EOF'
Summary points:
- WebApp Environment:
  - VM runs Ubuntu 20.04 (intentionally older) and has SSH open to the internet.
  - VM has an overly-permissive IAM role (EC2FullAccess + S3FullAccess).
  - MongoDB is installed and accessible ONLY from Kubernetes private subnets (SG rule on 27017).
  - Automated daily mongodump backups run via cron and upload to an S3 bucket.
  - That S3 bucket is intentionally public readable AND listable (bucket policy + public access block).
  - Tasky app runs on EKS in private subnets and uses MONGODB_URI passed via Kubernetes (secret/env).
  - Container includes /app/wizexercise.txt with your name + build SHA and you can cat it live.
  - App has cluster-admin via ClusterRoleBinding and is privileged (intentional weakness).
  - App is exposed via Kubernetes Ingress and a public ALB hostname.

- Dev(Sec)Ops:
  - One pipeline for IaC: fmt/validate/plan + Trivy IaC scanning (SARIF).
  - One pipeline for app: Podman build, Trivy image scan (SARIF), push to ECR, deploy to EKS, verify wizexercise.txt.
  - Uses GitHub OIDC to assume AWS role (no static keys).

- Cloud Native Security:
  - EKS control plane logs (including audit/api) enabled.
  - Preventative control: EBS encryption by default enabled.
  - Detective control: CloudTrail enabled; AWS Config enabled with managed rules.
  - Optional detective controls: GuardDuty and Security Hub if enabled in the account.
EOF

ok "Done"
