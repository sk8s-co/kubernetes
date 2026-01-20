# How to Create Patches

Patches in this directory are applied to the Kubernetes source before building kubelet.

## Directory Structure

Patch folders are named using [semver ranges](https://github.com/npm/node-semver#ranges). Patches are applied if the build version satisfies the folder's range.

```
patches/
  ^1.34/          # Patches for Kubernetes >=1.34.0 <2.0.0
    etag-cache-control.patch
  how.md          # This file
```

Common range patterns:
- `^1.34` - matches >=1.34.0 <2.0.0 (any 1.x starting from 1.34)
- `~1.34.0` - matches >=1.34.0 <1.35.0 (only 1.34.x)
- `>=1.35.0` - matches 1.35.0 and above

## Creating a New Patch

1. Clone the target Kubernetes version:
   ```bash
   git clone https://github.com/kubernetes/kubernetes.git -b v1.34.0 --depth=1 /tmp/kubernetes
   cd /tmp/kubernetes
   ```

2. Make your changes to the source files.

3. Generate the patch (place in appropriate semver range folder):
   ```bash
   git diff > /path/to/patches/^1.34/my-patch.patch
   ```

4. Verify the patch applies cleanly:
   ```bash
   git checkout .  # Reset changes
   git apply --check my-patch.patch
   ```

## Patch Format

Patches use standard unified diff format. Example:

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

## Build Behavior

- Patches are applied with `git apply --verbose --check` first to verify
- If any patch fails to apply, the build fails
- Applied changes are shown via `git diff HEAD` in the build log

## Tips

- Keep patches minimal and focused on a single change
- Use descriptive filenames (e.g., `etag-cache-control.patch`)
- Test patches locally before committing
- When upgrading Kubernetes versions, verify patches still apply or update them
