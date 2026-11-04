#!/usr/bin/env python3
"""Create a tiny *random-weight* GGUF with the OLMo 2 architecture.

This is NOT the OLMo 2 1B model and produces gibberish. It exists only so the
llama.cpp inference path (llama-server, streaming, token accounting, queueing)
can be tested end-to-end in CI or sandboxes where the real 1.5 GB weights
cannot be downloaded. Production uses scripts/download_model.sh.

    python scripts/make_tiny_test_model.py models/tiny-olmo2-test.gguf
"""
import sys

import numpy as np
from gguf import GGUFWriter, TokenType


def bytes_to_unicode():
    bs = list(range(ord("!"), ord("~") + 1)) + list(range(ord("¡"), ord("¬") + 1)) + list(range(ord("®"), ord("ÿ") + 1))
    cs = bs[:]
    n = 0
    for b in range(256):
        if b not in bs:
            bs.append(b)
            cs.append(256 + n)
            n += 1
    return dict(zip(bs, [chr(c) for c in cs]))


GEMMA3_TEMPLATE = (
    "{{ bos_token }}{%- if messages[0]['role'] == 'system' -%}"
    "{%- set first_user_prefix = messages[0]['content'] + '\n\n' -%}{%- set loop_messages = messages[1:] -%}"
    "{%- else -%}{%- set first_user_prefix = '' -%}{%- set loop_messages = messages -%}{%- endif -%}"
    "{%- for message in loop_messages -%}{%- set role = 'model' if message['role'] == 'assistant' else message['role'] -%}"
    "{{ '<start_of_turn>' + role + '\n' + (first_user_prefix if loop.first else '') }}{{ message['content'] | trim }}"
    "{{ '<end_of_turn>\n' }}{%- endfor -%}{%- if add_generation_prompt -%}{{ '<start_of_turn>model\n' }}{%- endif -%}"
)


def main(path: str, chat_template: str | None = None) -> None:
    rng = np.random.default_rng(42)
    n_embd, n_layer, n_head, n_ff, ctx = 64, 2, 4, 128, 4096
    b2u = bytes_to_unicode()
    merges = ["h e", "Ġ t", "Ġt he", "i n", "e r", "Ġ a", "o n"]
    merged = [m.replace(" ", "") for m in merges]
    tokens = [b2u[b] for b in range(256)] + merged + ["<|endoftext|>", "<|pad|>"]
    types = [TokenType.NORMAL] * (256 + len(merged)) + [TokenType.CONTROL, TokenType.CONTROL]
    eos_id = tokens.index("<|endoftext|>")
    n_vocab = len(tokens)

    w = GGUFWriter(path, "olmo2")
    w.add_name("kiwion-tiny-olmo2-test (random weights, NOT OLMo)")
    w.add_context_length(ctx)
    w.add_embedding_length(n_embd)
    w.add_block_count(n_layer)
    w.add_feed_forward_length(n_ff)
    w.add_head_count(n_head)
    w.add_head_count_kv(n_head)
    w.add_layer_norm_rms_eps(1e-6)
    w.add_rope_freq_base(500000.0)
    w.add_file_type(0)
    w.add_tokenizer_model("gpt2")
    w.add_tokenizer_pre("default")
    w.add_token_list(tokens)
    w.add_token_types(types)
    w.add_token_merges(merges)
    w.add_bos_token_id(eos_id)
    w.add_eos_token_id(eos_id)
    w.add_pad_token_id(eos_id + 1)
    w.add_add_bos_token(False)
    if chat_template:
        w.add_chat_template(chat_template)

    def t(name, *shape, ones=False):
        arr = np.ones(shape, dtype=np.float32) if ones else (rng.standard_normal(shape) * 0.05).astype(np.float32)
        w.add_tensor(name, arr)

    t("token_embd.weight", n_vocab, n_embd)
    t("output_norm.weight", n_embd, ones=True)
    t("output.weight", n_vocab, n_embd)
    for i in range(n_layer):
        p = f"blk.{i}."
        for n in ("attn_q", "attn_k", "attn_v", "attn_output"):
            t(p + n + ".weight", n_embd, n_embd)
        for n in ("attn_q_norm", "attn_k_norm", "post_attention_norm", "post_ffw_norm"):
            t(p + n + ".weight", n_embd, ones=True)
        t(p + "ffn_gate.weight", n_ff, n_embd)
        t(p + "ffn_up.weight", n_ff, n_embd)
        t(p + "ffn_down.weight", n_embd, n_ff)

    w.write_header_to_file()
    w.write_kv_data_to_file()
    w.write_tensors_to_file()
    w.close()
    print("wrote", path)


if __name__ == "__main__":
    # --gemma-template embeds a Gemma 3 style chat template (tests the "model template" path)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    main(args[0] if args else "models/tiny-olmo2-test.gguf",
         GEMMA3_TEMPLATE if "--gemma-template" in sys.argv else None)
