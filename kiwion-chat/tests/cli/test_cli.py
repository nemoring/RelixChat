import subprocess
import sys

from kiwion_cli.main import build_parser


def test_parser_has_all_commands():
    p = build_parser()
    for argv in (["chat"], ["status"], ["models"], ["server", "start"], ["server", "stop"], ["benchmark"]):
        assert p.parse_args(argv).func


def test_secret_and_version():
    out = subprocess.run([sys.executable, "-m", "kiwion_cli", "secret"], capture_output=True, text=True)
    assert out.returncode == 0 and len(out.stdout.strip()) == 64
    out = subprocess.run([sys.executable, "-m", "kiwion_cli", "--version"], capture_output=True, text=True)
    assert "kiwion 1.0.0" in out.stdout


def test_server_start_status_chat_stop_with_mock_engine(tmp_path):
    import os
    env = {**os.environ, "KIWION_HOME": str(tmp_path), "KIWION_INFERENCE_SECRET": "z" * 64,
           "KIWION_INFERENCE_PORT": "18290", "KIWION_INFERENCE_URL": "http://127.0.0.1:18290"}
    run = lambda *a, **kw: subprocess.run([sys.executable, "-m", "kiwion_cli", *a], env=env, capture_output=True,
                                          text=True, timeout=60, **kw)
    try:
        r = run("server", "start", "--engine", "mock", "--wait", "30")
        assert r.returncode == 0, r.stdout + r.stderr
        r = run("status")
        assert "ready" in r.stdout and "engine=mock" in r.stdout
        r = run("chat", input="привет киви\n/exit\n")
        assert "привет киви" in r.stdout
        r = run("benchmark", "--runs", "1", "--max-tokens", "8")
        assert r.returncode == 0 and "tok/s" in r.stdout
    finally:
        r = run("server", "stop")
    assert "stopped: inference" in r.stdout
    assert run("status").returncode == 1
