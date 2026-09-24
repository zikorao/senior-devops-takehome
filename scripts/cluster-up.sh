#!/usr/bin/env bash
# Create the kind cluster and apply the takehome namespace through Terraform.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/terraform.sh" apply
