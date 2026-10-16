#!/usr/bin/env python3
"""Подпись APK по схеме APK Signature Scheme v2 (без Android SDK).

Используется, когда apksigner недоступен. Ключ — PKCS#12 (например,
отладочный keystore Godot, сконвертированный keytool -importkeystore).

    python3 tools/sign_apk_v2.py in.apk out.apk key.p12 пароль

Подпись v2 проверяется Android 7.0+ (API 24). Подпись v1 (JAR) не ставится.
"""
import hashlib
import struct
import sys

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.serialization import pkcs12

CHUNK = 1024 * 1024
SIG_RSA_PKCS1_SHA256 = 0x0103
V2_BLOCK_ID = 0x7109871A
MAGIC = b"APK Sig Block 42"


def lp(data: bytes) -> bytes:
    """Префикс длины uint32 LE."""
    return struct.pack("<I", len(data)) + data


def find_eocd(apk: bytes) -> int:
    for i in range(len(apk) - 22, max(-1, len(apk) - 22 - 65536), -1):
        if apk[i:i + 4] == b"PK\x05\x06":
            return i
    raise ValueError("EOCD не найден")


def chunk_digest(sections) -> bytes:
    digests = []
    for sec in sections:
        for off in range(0, len(sec), CHUNK):
            part = sec[off:off + CHUNK]
            digests.append(hashlib.sha256(b"\xa5" + struct.pack("<I", len(part)) + part).digest())
    return hashlib.sha256(b"\x5a" + struct.pack("<I", len(digests)) + b"".join(digests)).digest()


def main() -> None:
    src, dst, p12_path, password = sys.argv[1:5]
    apk = open(src, "rb").read()
    eocd = find_eocd(apk)
    cd_size, cd_offset = struct.unpack("<II", apk[eocd + 12:eocd + 20])
    if apk[cd_offset - 16:cd_offset] == MAGIC:
        raise SystemExit("APK уже содержит блок подписи")
    entries = apk[:cd_offset]
    central = apk[cd_offset:eocd]
    eocd_data = apk[eocd:]

    key, cert, _ = pkcs12.load_key_and_certificates(open(p12_path, "rb").read(), password.encode())
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    pub_der = key.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)

    digest = chunk_digest([entries, central, eocd_data])
    digests = lp(lp(struct.pack("<I", SIG_RSA_PKCS1_SHA256) + lp(digest)))
    certs = lp(lp(cert_der))
    attrs = lp(b"")
    signed_data = digests + certs + attrs
    signature = key.sign(signed_data, padding.PKCS1v15(), hashes.SHA256())
    signatures = lp(lp(struct.pack("<I", SIG_RSA_PKCS1_SHA256) + lp(signature)))
    signer = lp(signed_data) + signatures + lp(pub_der)
    v2_value = lp(lp(signer))

    pair = struct.pack("<Q", 4 + len(v2_value)) + struct.pack("<I", V2_BLOCK_ID) + v2_value
    block_size = len(pair) + 8 + 16
    block = struct.pack("<Q", block_size) + pair + struct.pack("<Q", block_size) + MAGIC

    new_eocd = bytearray(eocd_data)
    struct.pack_into("<I", new_eocd, 16, cd_offset + len(block))
    with open(dst, "wb") as f:
        f.write(entries + block + central + bytes(new_eocd))
    print("Подписано (v2):", dst)


if __name__ == "__main__":
    main()
