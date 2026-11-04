"""Model identity: human-readable name and API id, derived from the GGUF file name.

Kiwion can run any chat model llama.cpp supports. The name shown in the apps and the
id used by the Developer API come from KIWION_MODEL_NAME / KIWION_MODEL_ID when set,
otherwise from the file name (e.g. gemma-3-4b-it-Q4_K_M.gguf -> "Gemma 3 4B", "gemma-3-4b").
"""
from __future__ import annotations

import re
from pathlib import Path

# (regex on the lower-cased file name, display name, api id, license note)
KNOWN = [
    (r"olmo-?2.*1b", "OLMo 2 1B Instruct", "olmo-2-1b-instruct", "Apache 2.0 · Ai2"),
    (r"olmo-?2.*7b", "OLMo 2 7B Instruct", "olmo-2-7b-instruct", "Apache 2.0 · Ai2"),
    (r"gemma-?3.*27b", "Gemma 3 27B", "gemma-3-27b", "Gemma Terms of Use · Google"),
    (r"gemma-?3.*12b", "Gemma 3 12B", "gemma-3-12b", "Gemma Terms of Use · Google"),
    (r"gemma-?3.*4b", "Gemma 3 4B", "gemma-3-4b", "Gemma Terms of Use · Google"),
    (r"gemma-?3.*1b", "Gemma 3 1B", "gemma-3-1b", "Gemma Terms of Use · Google"),
    (r"qwen-?3.*4b", "Qwen3 4B", "qwen3-4b", "Apache 2.0 · Alibaba"),
    (r"qwen-?3.*1\.?7b", "Qwen3 1.7B", "qwen3-1.7b", "Apache 2.0 · Alibaba"),
    (r"qwen-?2\.5.*1\.5b", "Qwen2.5 1.5B", "qwen2.5-1.5b", "Apache 2.0 · Alibaba"),
    (r"llama-?3\.2.*3b", "Llama 3.2 3B", "llama-3.2-3b", "Llama 3.2 Community License · Meta"),
]
QUANT = re.compile(r"[-_.](q\d[\w]*|iq\d[\w]*|f16|bf16|f32|qat.*)$", re.I)


def identify(model_path: str, name: str = "", model_id: str = "") -> dict:
    stem = Path(model_path).name
    if stem.lower().endswith(".gguf"):
        stem = stem[:-5]
    low = stem.lower()
    for pattern, display, ident, lic in KNOWN:
        if re.search(pattern, low):
            return {"name": name or display, "id": model_id or ident, "license": lic, "family": ident.split("-")[0]}
    base = QUANT.sub("", stem)
    pretty = re.sub(r"[-_]+", " ", base).strip() or "Model"
    slug = re.sub(r"[^a-z0-9.]+", "-", base.lower()).strip("-") or "model"
    return {"name": name or pretty, "id": model_id or slug, "license": "", "family": slug.split("-")[0]}


def is_olmo(model_path: str) -> bool:
    return "olmo" in Path(model_path).name.lower()
