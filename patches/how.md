# How to Create Patches

Patches in this directory are applied to the Kubernetes source before building.

## Directory Structure

```
patches/
  ^1.35/                    # Patches for Kubernetes >=1.35.0 <2.0.0
    watch.patch
    shared-etcd-client.patch
    ...
  how.md                    # This file (process documentation)
  why.md                    # Patch explanations and rationale

experiments/                # Work-in-progress or failed experiments
  exec.patch                # Patches that didn't work out
  experiments.md            # Context and learnings
```

## Semver Range Folders

Patch folders are named using [semver ranges](https://github.com/npm/node-semver#ranges). Patches are applied only if the build version satisfies the folder's range.

Common range patterns:
- `^1.35` - matches >=1.35.0 <2.0.0 (any 1.x starting from 1.35)
- `~1.35.0` - matches >=1.35.0 <1.36.0 (only 1.35.x)
- `>=1.35.0` - matches 1.35.0 and above

## Creating a New Patch

### Option 1: From scratch

1. Clone the target Kubernetes version:
   ```bash
   git clone https://github.com/kubernetes/kubernetes.git -b v1.35.0 --depth=1 ~/kubernetes/kubernetes
   cd ~/kubernetes/kubernetes
   ```

2. Make your changes to the source files.

3. Generate the patch:
   ```bash
   git diff > ~/sk8s-co/kubernetes/patches/^1.35/my-feature.patch
   ```

4. Verify the patch applies cleanly:
   ```bash
   git checkout .  # Reset changes
   git apply --check ~/sk8s-co/kubernetes/patches/^1.35/my-feature.patch
   ```

### Option 2: Iterating on an existing patch

1. In your Kubernetes source checkout, apply existing patches:
   ```bash
   cd ~/kubernetes/kubernetes
   git checkout .  # Start clean
   git apply ~/sk8s-co/kubernetes/patches/^1.35/my-feature.patch
   ```

2. Make additional changes.

3. Regenerate the patch:
   ```bash
   git diff > ~/sk8s-co/kubernetes/patches/^1.35/my-feature.patch
   ```

## Patch Format

Patches use standard unified diff format:

```diff
diff --git a/path/to/file.go b/path/to/file.go
index abc123..def456 100644
--- a/path/to/file.go
+++ b/path/to/file.go
@@ -50,7 +50,7 @@ func Example() {
 	unchanged line
-	old line to remove
+	new line to add
 	unchanged line
```

## Documentation

**Always document your patches:**

1. **why.md** - Add a section explaining:
   - What the patch changes
   - Why it's needed (the problem it solves)
   - Any configuration options or environment variables
   - Files modified

2. **experiments/experiments.md** - For patches that didn't work:
   - What was attempted
   - Why it failed
   - What was learned
   - Potential future approaches

## Build Process

The Dockerfile applies patches automatically:

1. Clones Kubernetes at the specified version
2. Iterates through `patches/*/` directories
3. Checks if directory name (semver range) matches build version
4. Applies all `.patch` files in matching directories with `git apply`
5. Fails the build if any patch doesn't apply cleanly

Builds are triggered on push to main via GitHub Actions.

## Tips

- **Keep patches minimal** - One logical change per patch
- **Use descriptive filenames** - e.g., `watch-backoff-on-empty.patch`
- **Test locally first** - Apply and build before pushing
- **Version compatibility** - When Kubernetes updates, verify patches still apply
- **Move failed experiments** - Don't delete learnings, move to `experiments/`
