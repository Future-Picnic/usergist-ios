#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"

runtime_id="$({ xcrun simctl list runtimes available --json || true; } | jq -r '
  [
    .runtimes[]
    | select(.isAvailable == true)
    | select(.name | startswith("iOS "))
  ]
  | sort_by(.version | split(".") | map(tonumber))
  | last
  | .identifier // empty
')"

device_type_id="$({ xcrun simctl list devicetypes --json || true; } | jq -r '
  [
    .devicetypes[]
    | select(.name | startswith("iPhone "))
  ]
  | first
  | .identifier // empty
')"

if [[ -z "$runtime_id" ]]; then
  echo "::error::No available iOS Simulator runtime is installed on this runner."
  exit 1
fi

if [[ -z "$device_type_id" ]]; then
  echo "::error::No iPhone Simulator device type is installed on this runner."
  exit 1
fi

simulator_name="UserGist CI ${GITHUB_RUN_ID:-$$}-${GITHUB_RUN_ATTEMPT:-1}"
simulator_id="$(xcrun simctl create "$simulator_name" "$device_type_id" "$runtime_id")"

xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

cd "$repo_root/packages/sdk-ios"
xcodebuild \
  test \
  -scheme UserGistFeedback-Package \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  CODE_SIGNING_ALLOWED=NO
