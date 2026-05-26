#!/usr/bin/env bash
# Test script: deploy pd-disaggregation with facebook/opt-125m (2P, 1D)
# and verify preflight checks run without needing a separate rollout.
#
# Usage:
#   export NAMESPACE="llm-d-preflight-test"
#   ./test-preflight-deploy.sh
#
set -euo pipefail

NAMESPACE="${NAMESPACE:-llm-d-preflight-test}"
GUIDE_NAME="${GUIDE_NAME:-pd-disaggregation}"
GAIE_VERSION="${GAIE_VERSION:-v1.5.0}"
REPO_ROOT="$(git rev-parse --show-toplevel)"
OVERLAY_PATH="guides/${GUIDE_NAME}/modelserver/gpu/vllm/test-preflight-opt125m"

echo "=== Preflight Checks Deployment Test ==="
echo "Namespace:  ${NAMESPACE}"
echo "Model:      facebook/opt-125m"
echo "Replicas:   2 Prefill, 1 Decode"
echo "Preflight:  enabled (mode=pause)"
echo ""

echo "--- Step 1: Verify kustomize build renders correctly ---"
kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" > /dev/null
echo "OK: kustomize build succeeded"

echo ""
echo "--- Step 2: Verify ConfigMap is included in build ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "kind: ConfigMap"; then
    echo "OK: ConfigMap llm-d-preflight-checks is in the rendered output"
else
    echo "FAIL: ConfigMap not found in rendered output"
    exit 1
fi

echo ""
echo "--- Step 3: Verify LLMD_PRE_START_COMMAND env var is injected ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "name: LLMD_PRE_START_COMMAND"; then
    echo "OK: LLMD_PRE_START_COMMAND env var is present"
else
    echo "FAIL: LLMD_PRE_START_COMMAND env var not found"
    exit 1
fi

echo ""
echo "--- Step 4: Verify LLMD_PREFLIGHT_CHECKS=pause is set ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -A1 "name: LLMD_PREFLIGHT_CHECKS" | grep -q "value: pause"; then
    echo "OK: LLMD_PREFLIGHT_CHECKS=pause is configured"
else
    echo "FAIL: LLMD_PREFLIGHT_CHECKS=pause not found"
    exit 1
fi

echo ""
echo "--- Step 5: Verify bash -c wrapper is used ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "command:" && \
   kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "\- bash" && \
   kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "\- -c"; then
    echo "OK: command uses bash -c wrapper"
else
    echo "FAIL: bash -c wrapper not found"
    exit 1
fi

echo ""
echo "--- Step 6: Verify model is facebook/opt-125m ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "facebook/opt-125m"; then
    echo "OK: model is facebook/opt-125m"
else
    echo "FAIL: facebook/opt-125m not found"
    exit 1
fi

echo ""
echo "--- Step 7: Verify replicas (2P, 1D) ---"
PREFILL_REPLICAS=$(kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -A100 "name:.*prefill$" | grep "replicas:" | head -1 | awk '{print $2}')
DECODE_REPLICAS=$(kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -A100 "name:.*decode$" | grep "replicas:" | head -1 | awk '{print $2}')
if [ "${PREFILL_REPLICAS}" = "2" ] && [ "${DECODE_REPLICAS}" = "1" ]; then
    echo "OK: replicas are 2P, 1D"
else
    echo "FAIL: expected 2P/1D, got ${PREFILL_REPLICAS}P/${DECODE_REPLICAS}D"
    exit 1
fi

echo ""
echo "--- Step 8: Verify preflight-scripts volume mount exists ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -q "mountPath: /preflight"; then
    echo "OK: /preflight volume mount exists"
else
    echo "FAIL: /preflight mount not found"
    exit 1
fi

echo ""
echo "--- Step 9: Verify ConfigMap volume is optional ---"
if kustomize build "${REPO_ROOT}/${OVERLAY_PATH}" | grep -A4 "name: llm-d-preflight-checks" | grep -q "optional: true"; then
    echo "OK: ConfigMap volume is optional (no-op when absent)"
else
    echo "FAIL: ConfigMap volume should be optional"
    exit 1
fi

echo ""
echo "=== ALL CHECKS PASSED ==="
echo ""
echo "To deploy to a cluster:"
echo "  kubectl create namespace ${NAMESPACE}"
echo "  kubectl apply -k ${OVERLAY_PATH} -n ${NAMESPACE}"
echo ""
echo "The preflight checks script is deployed WITH the model server."
echo "No separate rollout is needed to enable preflight checks."
echo ""
echo "To verify preflight checks run in pod logs:"
echo "  kubectl logs -n ${NAMESPACE} -l llm-d.ai/role=prefill -c modelserver | grep preflight"
echo "  kubectl logs -n ${NAMESPACE} -l llm-d.ai/role=decode -c modelserver | grep preflight"
