#!/usr/bin/env bash
# Apply or destroy the local kind environment. State stays in deploy/terraform and is gitignored.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
action="${1:?usage: terraform.sh apply|destroy}"

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
export TF_IN_AUTOMATION=1
export TF_VAR_image_tag="${IMAGE_TAG:-local}"

case "$action" in
  apply|destroy) ;;
  *)
    echo "usage: $0 apply|destroy" >&2
    exit 2
    ;;
esac

terraform -chdir="$ROOT/deploy/terraform" init -input=false
terraform -chdir="$ROOT/deploy/terraform" "$action" -input=false -auto-approve
