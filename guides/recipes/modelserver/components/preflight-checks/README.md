# Preflight Checks Component

A reusable kustomize component that deploys a Python-based preflight checks script and configures model server pods to run it before vLLM starts.

## What It Does

- Deploys a `llm-d-preflight-checks` ConfigMap containing a diagnostic script
- Patches all Deployments to set `LLMD_PRE_START_COMMAND` and `LLMD_PREFLIGHT_CHECKS` environment variables
- The script runs automatically before vLLM starts (via the `bash -c` wrapper in base patches)

## Checks Performed

| Check | What It Validates |
|-------|-------------------|
| GPU availability | `nvidia-smi` detects GPUs and reports their names |
| DNS resolution | `kubernetes.default.svc` resolves (cluster networking OK) |
| NIXL port | Port 5600 is bindable (no conflicts with KV transfer) |
| Shared memory | `/dev/shm` is mounted with at least 1 GiB |

## LLMD_PREFLIGHT_CHECKS Modes

| Value | Behavior |
|-------|----------|
| unset or empty | All checks run; failures are logged as warnings, vLLM starts anyway |
| `pause` | All checks run; on failure the pod sleeps indefinitely for debugging |
| `strict` | All checks run; on failure the script exits non-zero, preventing vLLM from starting |

## Usage

### Option 1: Include at deploy time (kustomize component)

Add the component to your overlay's `kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base
components:
  - ../../../../../recipes/modelserver/components/preflight-checks
```

This deploys the ConfigMap and injects the env vars in a single `kubectl apply` — no separate rollout needed.

### Option 2: Enable post-deploy (no rollout of base patches required)

The base patches already include:
- A `bash -c` wrapper that evaluates `${LLMD_PRE_START_COMMAND}` at runtime
- An optional ConfigMap volume mount at `/preflight`

To enable preflight checks on an existing deployment:

```bash
# 1. Deploy the ConfigMap with the script
kubectl apply -f guides/recipes/modelserver/components/preflight-checks/configmap.yaml -n $NAMESPACE

# 2. Set the env vars (triggers a rolling update)
kubectl set env deployment/<prefill-deployment-name> \
  LLMD_PRE_START_COMMAND="python3 /preflight/llm-d-preflight-checks.py" \
  LLMD_PREFLIGHT_CHECKS=pause -n $NAMESPACE

kubectl set env deployment/<decode-deployment-name> \
  LLMD_PRE_START_COMMAND="python3 /preflight/llm-d-preflight-checks.py" \
  LLMD_PREFLIGHT_CHECKS=pause -n $NAMESPACE
```

### Option 3: Disable preflight checks

```bash
kubectl set env deployment/<deployment-name> LLMD_PRE_START_COMMAND- LLMD_PREFLIGHT_CHECKS- -n $NAMESPACE
```

## Verifying Preflight Checks Ran

```bash
kubectl logs -n $NAMESPACE -l llm-d.ai/role=prefill -c modelserver | grep "\[preflight\]"
kubectl logs -n $NAMESPACE -l llm-d.ai/role=decode -c modelserver | grep "\[preflight\]"
```

Expected output when all checks pass:

```
[preflight] Starting llm-d preflight checks (mode=pause)
[preflight] GPUs detected: 1
[preflight]   GPU 0: NVIDIA H100 80GB HBM3
[preflight] DNS resolution: OK (kubernetes.default.svc)
[preflight] NIXL port 5600: bindable
[preflight] /dev/shm size: 20.0 GiB
[preflight] All checks passed
```

## Customizing the Script

To add your own checks, edit `configmap.yaml` and add a new check function:

```python
def check_my_custom_thing():
    """Describe what this checks."""
    # Return True for pass, False for fail
    return True
```

Then add it to the `checks` list in `main()`:

```python
checks = [
    ...
    ("My custom check", check_my_custom_thing),
]
```
