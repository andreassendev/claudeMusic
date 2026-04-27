#!/usr/bin/env bash
# Detect GPU capabilities for claude-music
# Supports: NVIDIA (CUDA), Apple Silicon (MPS), CPU-only fallback
# Output: JSON with gpu_name, driver, vram/ram total, tier, recommendations
set -euo pipefail

# ── Apple Silicon (MPS) ────────────────────────────────────────────────
if [[ "$(uname -s)" == "Darwin" ]] && [[ "$(uname -m)" == "arm64" ]]; then
    CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Apple Silicon")
    UNIFIED_RAM_BYTES=$(sysctl -n hw.memsize 2>/dev/null || echo 0)
    UNIFIED_RAM_MB=$(( UNIFIED_RAM_BYTES / 1024 / 1024 ))
    # On Apple Silicon, GPU shares unified memory — typically ~75% available
    EFFECTIVE_VRAM_MB=$(( UNIFIED_RAM_MB * 3 / 4 ))

    if [ "$EFFECTIVE_VRAM_MB" -ge 16000 ]; then
        TIER="high"; REC_MODEL="acestep-v15-turbo"; REC_LM="acestep-5Hz-lm-0.6B"
    elif [ "$EFFECTIVE_VRAM_MB" -ge 8000 ]; then
        TIER="standard"; REC_MODEL="acestep-v15-turbo"; REC_LM="none"
    else
        TIER="low"; REC_MODEL="acestep-v15-turbo"; REC_LM="none"
    fi

    cat <<EOF
{
  "gpu_detected": true,
  "platform": "mps",
  "gpu_name": "$CHIP",
  "driver_version": "Metal",
  "vram_total_mb": $UNIFIED_RAM_MB,
  "vram_free_mb": $EFFECTIVE_VRAM_MB,
  "vram_used_mb": 0,
  "compute_capability": "metal",
  "tier": "$TIER",
  "recommended_model": "$REC_MODEL",
  "recommended_lm": "$REC_LM"
}
EOF
    exit 0
fi

# ── NVIDIA (CUDA) ──────────────────────────────────────────────────────
if command -v nvidia-smi &>/dev/null; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
    DRIVER=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
    VRAM_TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
    VRAM_FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
    VRAM_USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)
    CUDA_CAP=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader,nounits 2>/dev/null | head -1 | xargs)

    if [ "$VRAM_FREE" -ge 16000 ]; then
        TIER="xl"; REC_MODEL="acestep-v15-xl-turbo"; REC_LM="acestep-5Hz-lm-1.7B"
    elif [ "$VRAM_FREE" -ge 12000 ]; then
        TIER="high"; REC_MODEL="acestep-v15-turbo"; REC_LM="acestep-5Hz-lm-1.7B"
    elif [ "$VRAM_FREE" -ge 8000 ]; then
        TIER="standard"; REC_MODEL="acestep-v15-turbo"; REC_LM="acestep-5Hz-lm-0.6B"
    elif [ "$VRAM_FREE" -ge 4000 ]; then
        TIER="low"; REC_MODEL="acestep-v15-turbo"; REC_LM="none"
    else
        TIER="minimal"; REC_MODEL="acestep-v15-turbo"; REC_LM="none"
    fi

    cat <<EOF
{
  "gpu_detected": true,
  "platform": "cuda",
  "gpu_name": "$GPU_NAME",
  "driver_version": "$DRIVER",
  "vram_total_mb": $VRAM_TOTAL,
  "vram_free_mb": $VRAM_FREE,
  "vram_used_mb": $VRAM_USED,
  "compute_capability": "$CUDA_CAP",
  "tier": "$TIER",
  "recommended_model": "$REC_MODEL",
  "recommended_lm": "$REC_LM"
}
EOF
    exit 0
fi

# ── CPU fallback ───────────────────────────────────────────────────────
echo '{"gpu_detected":false,"platform":"cpu","error":"No GPU detected (NVIDIA or Apple Silicon)","tier":"minimal","recommended_model":"acestep-v15-turbo","recommended_lm":"none"}'
