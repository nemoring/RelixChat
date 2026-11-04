"""OLMo 2 Instruct chat template.

This reproduces the Jinja template shipped with allenai/OLMo-2-0425-1B-Instruct
(tokenizer_config.json) so that prompts are byte-identical to what the model was
trained with, independent of the template embedded in a GGUF file.

    {{ bos_token }}
    <|system|>\n{system}\n
    <|user|>\n{user}\n
    <|assistant|>\n{assistant}{eos_token}\n
    ...
    <|assistant|>\n          <- generation prompt

bos_token == eos_token == "<|endoftext|>"
"""
from __future__ import annotations

from typing import Iterable, Mapping

BOS = "<|endoftext|>"
EOS = "<|endoftext|>"
STOP_SEQUENCES = ["<|endoftext|>", "<|user|>", "<|system|>"]

DEFAULT_SYSTEM_PROMPT = (
    "You are Kiwion, a friendly and helpful AI assistant in the Kiwion Chat app "
    "made by Kiwi_Fuzzy. Your mascot is a small fluffy kiwi bird. Answer clearly "
    "and concisely. Use Markdown for formatting and fenced code blocks for code.\n"
    "\n"
    "LANGUAGE RULES:\n"
    "- Always respond in the same language as the user.\n"
    "- If the user writes in Russian, respond entirely in Russian.\n"
    "- English is allowed only for technical terms, code, proper names, and direct quotations.\n"
    "- Never switch languages mid-response.\n"
    "- Do not add English follow-up questions to Russian answers."
)

VALID_ROLES = {"system", "user", "assistant"}


def render_olmo2(messages: Iterable[Mapping[str, str]], add_generation_prompt: bool = True,
                 include_bos: bool = True) -> str:
    msgs = list(messages)
    out = [BOS] if include_bos else []
    for i, m in enumerate(msgs):
        role = m.get("role")
        content = m.get("content") or ""
        is_last = i == len(msgs) - 1
        if role == "system":
            out.append("<|system|>\n" + content + "\n")
        elif role == "user":
            out.append("<|user|>\n" + content + "\n")
        elif role == "assistant":
            if not is_last:
                out.append("<|assistant|>\n" + content + EOS + "\n")
            else:
                out.append("<|assistant|>\n" + content + EOS)
        else:
            raise ValueError(f"unsupported role: {role!r}")
        if is_last and add_generation_prompt:
            out.append("<|assistant|>\n")
    return "".join(out)


def with_default_system(messages: list[dict], system_prompt: str | None = DEFAULT_SYSTEM_PROMPT) -> list[dict]:
    if system_prompt and not any(m.get("role") == "system" for m in messages):
        return [{"role": "system", "content": system_prompt}] + list(messages)
    return list(messages)


def estimate_tokens(text: str) -> int:
    """Cheap token estimate (≈4 chars/token) used only for pre-flight budget checks.

    Real usage accounting always uses the token counts reported by llama.cpp.
    """
    return max(1, (len(text) + 3) // 4)


def trim_history(messages: list[dict], max_prompt_tokens: int) -> list[dict]:
    """Drop the oldest non-system turns until the estimated prompt fits the context."""
    system = [m for m in messages if m.get("role") == "system"]
    rest = [m for m in messages if m.get("role") != "system"]
    def size(ms):
        return sum(estimate_tokens(m.get("content", "")) + 4 for m in ms)
    while len(rest) > 1 and size(system + rest) > max_prompt_tokens:
        rest.pop(0)
    return system + rest
