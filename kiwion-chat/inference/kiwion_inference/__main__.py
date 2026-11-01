"""Run: python -m kiwion_inference"""
import logging
import ssl

import uvicorn

from kiwion_shared.redact import install_redaction

from .app import create_app
from .config import InferenceConfig


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    install_redaction()
    cfg = InferenceConfig()
    app = create_app(cfg)
    kwargs = {}
    if cfg.ssl_certfile and cfg.ssl_keyfile:
        kwargs.update(ssl_certfile=cfg.ssl_certfile, ssl_keyfile=cfg.ssl_keyfile)
        if cfg.ssl_client_ca:  # mutual TLS: only clients with a cert signed by this CA may connect
            kwargs.update(ssl_ca_certs=cfg.ssl_client_ca, ssl_cert_reqs=ssl.CERT_REQUIRED)
    elif cfg.host not in ("127.0.0.1", "localhost", "::1"):
        logging.getLogger("kiwion.inference").warning(
            "Listening on %s without TLS. Use a WireGuard/Tailscale tunnel or set "
            "KIWION_INFERENCE_SSL_CERT/KEY.", cfg.host)
    uvicorn.run(app, host=cfg.host, port=cfg.port, log_level="info", access_log=False, **kwargs)


if __name__ == "__main__":
    main()
