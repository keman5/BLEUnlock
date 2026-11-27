#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/../.." && pwd)"
test_dir="$(mktemp -d /tmp/bleunlock-authorization-test.XXXXXX)"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -swift-version 5 \
    "$project_dir/BLEUnlock/AuthorizationPromptMonitor.swift" \
    "$project_dir/Tests/AuthorizationPromptPolicy/main.swift" \
    -o "$test_dir/policy-tests"
"$test_dir/policy-tests"
