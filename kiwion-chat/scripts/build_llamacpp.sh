#!/usr/bin/env bash
# Build llama.cpp (llama-server, llama-quantize, llama-bench, llama-cli) into third_party/llama.cpp.
#
#   scripts/build_llamacpp.sh            # CPU build tuned for THIS machine (GGML_NATIVE)
#   KIWION_VULKAN=1 scripts/build_llamacpp.sh   # + Vulkan backend (e.g. Intel HD 620 via Mesa ANV) — experimental
#
# Intel Pentium 4417U has SSE4.2 but no AVX/AVX2; GGML_NATIVE=ON makes the compiler use exactly
# the instruction set of the CPU you build on, so build ON the inference machine itself.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="$ROOT/third_party/llama.cpp"
REF="${LLAMA_CPP_REF:-785322d17f2d51e5185cf996a1f4e46d87640841}"   # tested commit; override to update
JOBS="${JOBS:-$(nproc)}"

if [ ! -d "$DIR/.git" ]; then
  mkdir -p "$ROOT/third_party"
  git clone https://github.com/ggml-org/llama.cpp "$DIR"
fi
cd "$DIR"
git fetch --depth 1 origin "$REF" 2>/dev/null || git fetch origin
git checkout -q "$REF" 2>/dev/null || echo "warning: could not checkout $REF, building current checkout"

FLAGS=(-DCMAKE_BUILD_TYPE=Release -DGGML_NATIVE=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON)
if [ "${KIWION_VULKAN:-0}" = "1" ]; then
  FLAGS+=(-DGGML_VULKAN=ON)   # needs libvulkan-dev + glslc (Ubuntu: sudo apt install libvulkan-dev glslc mesa-vulkan-drivers)
fi
cmake -B build "${FLAGS[@]}"
# low-RAM machines: limit parallel compile jobs (each job can take ~1 GB)
cmake --build build -j "$JOBS" --target llama-server llama-quantize llama-bench llama-cli
echo
echo "built: $DIR/build/bin/llama-server"
grep -o -m1 -E '\b(avx2|avx|sse4_2)\b' /proc/cpuinfo | head -1 | sed 's/^/best SIMD on this CPU: /' || true
