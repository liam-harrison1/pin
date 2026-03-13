#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

say() {
  printf '==> %s\n' "$1"
}

warn() {
  printf 'WARN: %s\n' "$1"
}

require_file() {
  local path="$1"

  if [[ ! -e "$path" ]]; then
    printf 'ERROR: required path missing: %s\n' "$path" >&2
    exit 1
  fi
}

pick_swift_sdk() {
  local sdk_dir="/Library/Developer/CommandLineTools/SDKs"
  local candidate

  for candidate in \
    "${DESKPINS_SWIFT_SDK:-}" \
    "$sdk_dir/MacOSX15.4.sdk" \
    "$sdk_dir/MacOSX15.sdk" \
    "$sdk_dir/MacOSX.sdk"
  do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

prepare_swift_environment() {
  local sdk_path

  sdk_path="$(pick_swift_sdk)" || {
    printf 'ERROR: unable to find a usable macOS SDK for swift verification\n' >&2
    exit 1
  }

  mkdir -p .build/cache/clang .build/cache/swiftpm

  export SDKROOT="$sdk_path"
  export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/cache/clang"
  export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/cache/swiftpm"
}

say "Verify repo structure"
require_file "AGENTS.md"
require_file "README.md"
require_file "deskpins-project-book-v2.md"
require_file "Docs/product-spec.md"
require_file "Docs/architecture.md"
require_file "Docs/mvp-checklist.md"
require_file "Docs/permission-model.md"
require_file "Docs/release-plan.md"
require_file "Scripts/README.md"

say "Check for conflict markers"
if command -v rg >/dev/null 2>&1; then
  if rg -n '^(<<<<<<<|=======|>>>>>>>)' . \
    --glob '!**/.git/**' \
    --glob '!Core/**/.gitkeep' \
    --glob '!**/node_modules/**'
  then
    printf 'ERROR: merge conflict markers detected\n' >&2
    exit 1
  fi
else
  if grep -R -nE '^(<<<<<<<|=======|>>>>>>>)' . \
    --exclude-dir=.git \
    --exclude=.gitkeep
  then
    printf 'ERROR: merge conflict markers detected\n' >&2
    exit 1
  fi
fi

say "Run shell script checks"
if command -v bash >/dev/null 2>&1; then
  bash -n Scripts/*.sh
fi

say "Validate git workflow support files"
require_file ".github/pull_request_template.md"
require_file ".github/workflows/verify.yml"
require_file ".pre-commit-config.yaml"

swift_files=()
while IFS= read -r file; do
  swift_files+=("$file")
done < <(find . \
  -path './.git' -prune -o \
  -name '*.swift' -print)

if (( ${#swift_files[@]} > 0 )); then
  say "Swift sources detected"
  prepare_swift_environment

  if [[ -f "Package.swift" ]]; then
    say "swift build"
    swift build

    if swift package dump-package >/dev/null 2>&1; then
      for smoke_dir in Tools/*SmokeTests; do
        if [[ -d "$smoke_dir" ]]; then
          smoke_name="$(basename "$smoke_dir")"
          say "swift run $smoke_name"
          swift run "$smoke_name"
        fi
      done
    fi
  else
    warn "Skipping swift build/test because Package.swift is not present"
  fi

  if command -v swiftlint >/dev/null 2>&1; then
    say "swiftlint"
    swiftlint
  else
    warn "swiftlint not installed; skipping lint"
  fi

  xcode_projects=()
  while IFS= read -r file; do
    xcode_projects+=("$file")
  done < <(find . \
    -path './.git' -prune -o \
    -name '*.xcodeproj' -print)

  xcode_workspaces=()
  while IFS= read -r file; do
    xcode_workspaces+=("$file")
  done < <(find . \
    -path './.git' -prune -o \
    -name '*.xcworkspace' -print)

  if (( ${#xcode_projects[@]} > 0 || ${#xcode_workspaces[@]} > 0 )); then
    scheme="${DESKPINS_XCODE_SCHEME:-}"

    if [[ -z "$scheme" ]]; then
      printf 'ERROR: Xcode project detected but DESKPINS_XCODE_SCHEME is not set\n' >&2
      exit 1
    fi

    destination="${DESKPINS_XCODE_DESTINATION:-platform=macOS}"

    if (( ${#xcode_workspaces[@]} > 0 )); then
      say "xcodebuild workspace build"
      xcodebuild \
        -workspace "${xcode_workspaces[0]}" \
        -scheme "$scheme" \
        -destination "$destination" \
        build
    else
      say "xcodebuild project build"
      xcodebuild \
        -project "${xcode_projects[0]}" \
        -scheme "$scheme" \
        -destination "$destination" \
        build
    fi
  fi
else
  warn "No Swift sources detected; skipping Swift-specific checks"
fi

say "Verification complete"
