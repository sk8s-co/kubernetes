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

# For local dev: if kubernetes submodule exists, cd into it
# In Docker: we're already in /kubernetes (WORKDIR)
if [ -e "$SCRIPT_DIR/kubernetes/.git" ]; then
    echo "Changing to kubernetes submodule directory"
    cd "$SCRIPT_DIR/kubernetes"
fi

# Fetch a URL using wget or curl
fetch_url() {
    local url="$1"
    local output="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O - "$url" >> "$output" || (echo "Failed to fetch $url" && return 1)
    else
        curl -sL "$url" >> "$output" || (echo "Failed to fetch $url" && return 1)
    fi
}

# Parse a remote patch line and return the URL
# Supported formats:
#   owner:branch      -> compare master...owner:kubernetes:branch (unmerged PRs)
#   pr:NUMBER         -> PR patch (works for merged PRs)
#   commit:SHA        -> specific commit patch
get_patch_url() {
    local line="$1"
    local type=$(echo "$line" | cut -d':' -f1)
    local value=$(echo "$line" | cut -d':' -f2-)

    case "$type" in
        pr)
            echo "https://github.com/kubernetes/kubernetes/pull/${value}.patch"
            ;;
        commit)
            echo "https://github.com/kubernetes/kubernetes/commit/${value}.patch"
            ;;
        *)
            # Default: owner:branch format
            echo "https://github.com/kubernetes/kubernetes/compare/master...${type}:kubernetes:${value}.diff"
            ;;
    esac
}

# Check if a line uses direct patch format (pr: or commit:) vs branch diff
is_direct_patch() {
    local line="$1"
    local type=$(echo "$line" | cut -d':' -f1)
    case "$type" in
        pr|commit) return 0 ;;
        *) return 1 ;;
    esac
}

apply_remote() {
    echo "=== Applying remote patches ==="

    # Configure git for commits
    git config user.email "build@localhost"
    git config user.name "Build"

    original_ref=$(git rev-parse HEAD)
    has_branch_patches=false
    has_direct_patches=false

    # First pass: categorize patches
    for range_dir in "$REMOTE_PATCHES_DIR"/*/; do
        [ -d "$range_dir" ] || continue
        for patch_file in "$range_dir"*; do
            [ -f "$patch_file" ] || continue
            while IFS= read -r line || [ -n "$line" ]; do
                line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                [ -z "$line" ] && continue
                if is_direct_patch "$line"; then
                    has_direct_patches=true
                else
                    has_branch_patches=true
                fi
            done < "$patch_file"
        done
    done

    # Apply branch-based patches (need master checkout + cherry-pick)
    if [ "$has_branch_patches" = true ]; then
        echo "--- Applying branch-based patches via cherry-pick ---"
        git fetch origin master --depth=1
        git checkout FETCH_HEAD

        for range_dir in "$REMOTE_PATCHES_DIR"/*/; do
            [ -d "$range_dir" ] || continue
            range=$(basename "$range_dir")
            mkdir -p "$REMOTE_CACHE_DIR/$range"
            for patch_file in "$range_dir"*; do
                [ -f "$patch_file" ] || continue
                patch_name=$(basename "$patch_file")
                output_file="$REMOTE_CACHE_DIR/$range/${patch_name}-branch.patch"
                > "$output_file"
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                    [ -z "$line" ] && continue
                    is_direct_patch "$line" && continue
                    url=$(get_patch_url "$line")
                    echo "Fetching branch patch: $url"
                    fetch_url "$url" "$output_file"
                done < "$patch_file"
                if [ -s "$output_file" ]; then
                    echo "Applying branch patch on master: $output_file"
                    git apply --verbose --check "$output_file"
                    git apply --verbose "$output_file"
                fi
            done
        done

        git add -A
        if ! git diff --cached --quiet; then
            git commit -m "Remote branch patches"
            remote_commit=$(git rev-parse HEAD)
            git checkout "$original_ref"
            git cherry-pick --no-commit "$remote_commit"
            echo "Branch patches cherry-picked successfully"
        else
            echo "No branch patches to apply"
            git checkout "$original_ref"
        fi
    fi

    # Apply direct patches (pr: and commit:) - apply directly to current ref
    # These are self-contained patches that don't require fetching master
    if [ "$has_direct_patches" = true ]; then
        echo "--- Applying direct patches (PR/commit) ---"
        for range_dir in "$REMOTE_PATCHES_DIR"/*/; do
            [ -d "$range_dir" ] || continue
            range=$(basename "$range_dir")
            mkdir -p "$REMOTE_CACHE_DIR/$range"
            for patch_file in "$range_dir"*; do
                [ -f "$patch_file" ] || continue
                patch_name=$(basename "$patch_file")
                output_file="$REMOTE_CACHE_DIR/$range/${patch_name}-direct.patch"
                > "$output_file"
                while IFS= read -r line || [ -n "$line" ]; do
                    line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
                    [ -z "$line" ] && continue
                    is_direct_patch "$line" || continue
                    url=$(get_patch_url "$line")
                    echo "Fetching direct patch: $url"
                    fetch_url "$url" "$output_file"
                done < "$patch_file"
                if [ -s "$output_file" ]; then
                    echo "Applying direct patch: $output_file"
                    # Try methods in order of preference:
                    # 1. --3way (best, but needs git history)
                    # 2. regular git apply (needs exact context)
                    # 3. patch with fuzz (most lenient, for shallow clones)
                    if git apply --3way --verbose "$output_file" 2>/dev/null; then
                        echo "Applied with 3-way merge"
                    elif git apply --verbose "$output_file" 2>/dev/null; then
                        echo "Applied with git apply"
                    else
                        echo "Git apply failed, trying patch with fuzz..."
                        patch -p1 --fuzz=3 < "$output_file"
                    fi
                fi
            done
        done
        echo "Direct patches applied successfully"
    fi
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
