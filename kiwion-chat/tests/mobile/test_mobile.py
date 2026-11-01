"""Android app checks that can run without an emulator.

* JVM unit tests for framework-independent classes (TapCounter, Pow), cross-checked with the server.
* Static checks of the built APK (if mobile/build_apk.sh was run).
"""
import hashlib
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
JAVA_SRC = ROOT / "mobile/app/src/main/java/dev/kiwifuzzy/kiwion"
APK = ROOT / "mobile/build/KiwionChat-1.0.0.apk"


@pytest.mark.skipif(not shutil.which("javac"), reason="JDK not installed")
def test_jvm_logic(tmp_path):
    srcs = [JAVA_SRC / "TapCounter.java", JAVA_SRC / "Pow.java", Path(__file__).with_name("MobileLogicTest.java")]
    subprocess.run(["javac", "-d", str(tmp_path)] + [str(s) for s in srcs], check=True, capture_output=True)
    out = subprocess.run(["java", "-cp", str(tmp_path), "MobileLogicTest"], capture_output=True, text=True)
    assert out.returncode == 0, out.stdout + out.stderr
    nonce = re.search(r"NONCE=(\d+)", out.stdout).group(1)
    # the server must accept the nonce found by the Android implementation
    from kiwion_backend.security import ProofOfWork
    d = hashlib.sha256(f"1700000000.abcdef.0123456789abcdef:{nonce}".encode()).digest()
    assert ProofOfWork.leading_zero_bits(d) >= 12


@pytest.mark.skipif(not (APK.exists() and shutil.which("aapt")), reason="APK not built")
def test_apk_manifest():
    out = subprocess.run(["aapt", "dump", "badging", str(APK)], capture_output=True, text=True).stdout
    assert "package: name='dev.kiwifuzzy.kiwion'" in out
    assert "versionName='1.0.0'" in out
    assert "launchable-activity: name='dev.kiwifuzzy.kiwion.SplashActivity'" in out
    assert "uses-permission: name='android.permission.INTERNET'" in out
    xml = subprocess.run(["aapt", "dump", "xmltree", str(APK), "AndroidManifest.xml"], capture_output=True, text=True).stdout
    assert "usesCleartextTraffic" in xml and "allowBackup" in xml
    if shutil.which("apksigner"):
        assert subprocess.run(["apksigner", "verify", str(APK)], capture_output=True).returncode == 0
