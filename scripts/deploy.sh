#!/usr/bin/env bash
# Apply the takehome namespace. Terraform generates app-credentials once and does not print them.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/terraform.sh" apply
