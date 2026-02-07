#!/bin/bash
set -e

# Usage: apply-patches.sh [remote|local|all]
#   remote - fetch and apply remote patches only
#   local  - apply local patches only
#   all    - both (default, used in Dockerfile)

PHASE="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Use env vars if set (Docker), otherwise use relative paths (local dev)
PATCHES_DIR="${PATCHES_DIR:-$SCRIPT_DIR/patches}"
REMOTE_PATCHES_DIR="${REMOTE_PATCHES_DIR:-$SCRIPT_DIR/remote-patches}"
# Fetched remote patches go to a cache dir (not tracked in git)
REMOTE_CACHE_DIR="${REMOTE_CACHE_DIR:-$SCRIPT_DIR/.cache/patches}"

apply_remote() {
    echo "=== Applying remote patches ==="

    # Remote patches are diffs against master, so we need to:
    # 1. Save current ref (e.g., v1.35.0)
    # 2. Checkout master and apply patches there
    # 3. Cherry-pick changes back to original ref

    original_ref=$(git rev-parse HEAD)

    # Fetch and checkout master
    echo "Fetching master for remote patch application..."
    git fetch origin master --depth=1
    git checkout FETCH_HEAD

    # Configure git for commits
    git config user.email "build@localhost"
    git config user.name "Build"

    # Apply remote patches on master
    for range_dir in "$REMOTE_PATCHES_DIR"/*/; do
        [ -d "$range_dir" ] || continue
        range=$(basename "$range_dir")
        mkdir -p "$REMOTE_CACHE_DIR/$range"
        for patch_file in "$range_dir"*; do
            [ -f "$patch_file" ] || continue
            patch_name=$(basename "$patch_file")
            output_file="$REMOTE_CACHE_DIR/$range/$patch_name.patch"
            # Clear existing fetched patch
            > "$output_file"
            while IFS= read -r line || [ -n "$line" ]; do
                line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                [ -z "$line" ] && continue
                owner=$(echo "$line" | cut -d':' -f1)
                branch=$(echo "$line" | cut -d':' -f2-)
                diff_url="https://github.com/kubernetes/kubernetes/compare/master...${owner}:kubernetes:${branch}.diff"
                echo "Fetching: $diff_url"
                if command -v wget >/dev/null 2>&1; then
                    wget -q -O - "$diff_url" >> "$output_file" || \
                        (echo "Failed to fetch $diff_url" && exit 1)
                else
                    curl -sL "$diff_url" >> "$output_file" || \
                        (echo "Failed to fetch $diff_url" && exit 1)
                fi
            done < "$patch_file"
            echo "Applying remote patch on master: $output_file"
            git apply --verbose --check "$output_file"
            git apply --verbose "$output_file"
        done
    done

    # Commit remote patches on master
    git add -A
    if git diff --cached --quiet; then
        echo "No remote patches to apply"
        git checkout "$original_ref"
        return
    fi
    git commit -m "Remote patches"
    remote_commit=$(git rev-parse HEAD)

    # Switch back to original ref and cherry-pick
    echo "Cherry-picking remote patches to original ref..."
    git checkout "$original_ref"
    git cherry-pick --no-commit "$remote_commit"
    echo "Remote patches applied successfully"
}

apply_local() {
    echo "=== Applying local patches ==="
    # Determine version for semver matching
    if [ -n "$KUBE_VERSION" ] && [ -n "$KUBE_VERSION_PATCH" ]; then
        current="${KUBE_VERSION}.${KUBE_VERSION_PATCH}"
    else
        # Try to detect from git tag
        current=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")
    fi

    for dir in "$PATCHES_DIR"/*/; do
        [ -d "$dir" ] || continue
        range=$(basename "$dir")

        # Skip if semver check fails (when semver is available)
        if command -v semver >/dev/null 2>&1 && [ -n "$current" ]; then
            if ! semver -r "$range" "$current" >/dev/null 2>&1; then
                echo "Skipping patches in $dir (range $range does not match $current)"
                continue
            fi
        fi

        for patch in "$dir"*.patch; do
            [ -f "$patch" ] || continue
            echo "Applying local patch: $patch"
            git apply --verbose --check "$patch"
            git apply --verbose "$patch"
        done
    done
}

commit_patches() {
    echo "=== Committing all patches ==="
    git config user.email "build@localhost"
    git config user.name "Build"
    git add -A && git commit -m "Apply patches" || echo "No changes to commit"
}

case "$PHASE" in
    remote)
        apply_remote
        ;;
    local)
        apply_local
        ;;
    all)
        apply_remote
        apply_local
        commit_patches
        ;;
    *)
        echo "Usage: $0 [remote|local|all]"
        exit 1
        ;;
esac
