#!/bin/bash
set -e

# Fetch remote patches and save them to /patches/
# Format: owner:branch -> github.com/kubernetes/kubernetes/compare/master...owner:kubernetes:branch.diff
for range_dir in /remote-patches/*/; do
    [ -d "$range_dir" ] || continue
    range=$(basename "$range_dir")
    mkdir -p "/patches/$range"
    for patch_file in "$range_dir"*; do
        [ -f "$patch_file" ] || continue
        patch_name=$(basename "$patch_file")
        while IFS= read -r line || [ -n "$line" ]; do
            line=$(echo "$line" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
            [ -z "$line" ] && continue
            owner=$(echo "$line" | cut -d':' -f1)
            branch=$(echo "$line" | cut -d':' -f2-)
            diff_url="https://github.com/kubernetes/kubernetes/compare/master...${owner}:kubernetes:${branch}.diff"
            echo "Fetching: $diff_url"
            wget -q -O - "$diff_url" >> "/patches/$range/$patch_name.patch" || \
                (echo "Failed to fetch $diff_url" && exit 1)
        done < "$patch_file"
    done
done

# Apply patches matching the current version
current="${KUBE_VERSION}.${KUBE_VERSION_PATCH}"
for dir in /patches/*/; do
    [ -d "$dir" ] || continue
    range=$(basename "$dir")
    if semver -r "$range" "$current" >/dev/null 2>&1; then
        for patch in "$dir"*.patch; do
            [ -f "$patch" ] || continue
            echo "Applying patch: $patch (range: $range)"
            git apply --verbose --check "$patch"
            git apply --verbose "$patch"
        done
    else
        echo "Skipping patches in $dir (range $range does not match $current)"
    fi
done

echo "=== Applied patches ==="
git diff HEAD
git config user.email "build@localhost"
git config user.name "Build"
git add -A && git commit -m "Apply patches"
