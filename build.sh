#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$project_dir"
destination=/Applications/BLEUnlock.app
artifact_dir="$project_dir/.artifacts"
mkdir -p "$artifact_dir"
build_dir="$(mktemp -d "$artifact_dir/local-build.XXXXXX")"
install_dir=
cleanup() {
    if [[ -n "$install_dir" ]]; then
        if [[ ! -e "$destination" && -d "$install_dir/previous.app" ]]; then
            mv "$install_dir/previous.app" "$destination" || return
        fi
        rm -rf "$install_dir"
    fi
    rm -rf "$build_dir"
    rmdir "$artifact_dir" 2>/dev/null || true
}
trap cleanup EXIT

if command -v go >/dev/null; then
    go clean -cache
fi

project_version="$(awk '/CURRENT_PROJECT_VERSION = / { sub(/;/, "", $3); print $3; exit }' BLEUnlock.xcodeproj/project.pbxproj)"
installed_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$destination/Contents/Info.plist" 2>/dev/null || true)"
if [[ "$installed_version" =~ ^[0-9]+$ ]] && ((installed_version > project_version)); then
    project_version="$installed_version"
fi
build_version=$((project_version + 1))

signing_settings=("CODE_SIGN_IDENTITY=${BLEUNLOCK_SIGN_IDENTITY:--}")
if [[ -n "${BLEUNLOCK_SIGN_TEAM:-}" ]]; then
    signing_settings+=("DEVELOPMENT_TEAM=$BLEUNLOCK_SIGN_TEAM")
fi
deployment_settings=()
sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${sdk_version%%.*} >= 27 )); then
    deployment_settings=(MACOSX_DEPLOYMENT_TARGET=12.0)
fi
xcodebuild -project BLEUnlock.xcodeproj -scheme BLEUnlock -configuration Release \
    -derivedDataPath "$build_dir" CURRENT_PROJECT_VERSION="$build_version" \
    SYMROOT="$build_dir/Build/Products" OBJROOT="$build_dir/Build/Intermediates.noindex" \
    SHARED_PRECOMPS_DIR="$build_dir/Build/Intermediates.noindex/PrecompiledHeaders" \
    "${signing_settings[@]}" ${deployment_settings[@]+"${deployment_settings[@]}"} build

built_app="$build_dir/Build/Products/Release/BLEUnlock.app"
actual_version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$built_app/Contents/Info.plist")"
[[ "$actual_version" == "$build_version" ]]
codesign --verify --deep --strict "$built_app"

install_dir="$(mktemp -d "$(dirname "$destination")/.bleunlock-install.XXXXXX")"
ditto "$built_app" "$install_dir/BLEUnlock.app"
codesign --verify --deep --strict "$install_dir/BLEUnlock.app"

running_pids="$(pgrep -f "^$destination/Contents/MacOS/BLEUnlock$" || true)"
if [[ -n "$running_pids" ]]; then
    while IFS= read -r pid; do
        kill -TERM "$pid" 2>/dev/null || true
        for attempt in {1..30}; do
            if ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.2
        done
        if kill -0 "$pid" 2>/dev/null; then
            echo "BLEUnlock is still running (PID $pid)." >&2
            exit 1
        fi
    done <<< "$running_pids"
fi

if [[ -e "$destination" ]]; then
    mv "$destination" "$install_dir/previous.app"
fi
mv "$install_dir/BLEUnlock.app" "$destination"
if [[ -n "$running_pids" ]]; then
    open -g -a "$destination"
fi
echo "Installed $destination (build $build_version)"
