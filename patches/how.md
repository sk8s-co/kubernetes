# How to Create Patches

Patches in this directory are applied to the Kubernetes source before building.

## Directory Structure

```
patches/
  ^1.35/                        # Local patches for Kubernetes >=1.35.0 <2.0.0
    01-etag-cache-control.patch
    01-shared-etcd-client.patch
    ...
  how.md                        # This file
  why.md                        # Patch explanations

remote-patches/
  ^1.35/                        # Remote patch definitions
    00-cnuss-kubernetes         # References fork branches (fetched at build time)

kubernetes/                     # Git submodule - scratchpad for patch development

.cache/patches/                 # Fetched remote patches (gitignored)

hack/
  apply-patches.sh              # Applies patches (supports remote/local/all)
```

## Patch Priority

1. **Remote patches** apply first - vetted changes targeting upstream
2. **Local patches** apply on top - project-specific customizations

Remote patches should be treated as important as mainline Kubernetes code.

## Creating a New Patch

The submodule is kept at the release tag (e.g., `v1.35.0`) for a clean state.
For patch development, temporarily switch to `master` since remote patches compare against master.

### Setup: Switch to master and apply existing patches

```bash
cd kubernetes

# Switch to master for patch development
git fetch origin
git reset --hard origin/master

# Apply remote patches first
../hack/apply-patches.sh remote

# Apply existing local patches
../hack/apply-patches.sh local

# Commit this state as your baseline
git add -A && git commit -m "baseline"
```

### Make your changes

1. Edit source files as needed.

2. Check which files you're touching:
   ```bash
   git diff --name-only
   ```

   If a file was already modified by an existing patch:
   - **Merge**: Incorporate changes into the existing patch
   - **Refactor**: Split the existing patch so yours can be independent

3. Generate your patch (diff from baseline):
   ```bash
   git diff > ../patches/^1.35/02-my-feature.patch
   ```

### Verify

```bash
# Reset and re-apply all patches
git reset --hard origin/master
../hack/apply-patches.sh remote
../hack/apply-patches.sh local

# Or test via Docker
cd ..
docker build --target patched -t k8s-patched-test .
```

### Cleanup: Reset submodule to release tag

```bash
cd kubernetes
git reset --hard v1.35.0
```

## Remote Patches

Remote patches reference GitHub fork branches. They're fetched at build time.

### Format

Files in `remote-patches/<range>/` contain one reference per line:

```
# Format: owner:branch
# Fetches: github.com/kubernetes/kubernetes/compare/master...owner:kubernetes:branch.diff

cnuss:issues/136823
```

### When to use

- Vetted changes targeting upstream that haven't merged yet
- Your own fork branches with upstream-quality changes

### Converting to local

Snapshot a remote patch to local:
```bash
curl -sL "https://github.com/kubernetes/kubernetes/compare/master...owner:kubernetes:branch.diff" \
  > patches/^1.35/02-feature.patch
```

Then remove the entry from `remote-patches/`.

## apply-patches.sh

```bash
./hack/apply-patches.sh remote  # Fetch and apply remote patches
./hack/apply-patches.sh local   # Apply local patches
./hack/apply-patches.sh all     # Both + commit (used in Dockerfile)
```

## Naming Convention

Use numbered prefixes for ordering:

```
00-*  # Reserved for remote-fetched patches
01-*  # Local patches
02-*  # Later patches can depend on earlier ones
```

## Documentation

Document patches in **why.md**:
- What the patch changes
- Why it's needed
- Configuration options
- Files modified
