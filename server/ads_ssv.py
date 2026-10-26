"""
AdMob rewarded-ad server-side verification (SSV).

Google calls our callback URL with the reward details plus an ECDSA signature.
We verify that signature against Google's published verifier keys so a client
can never mint coins by calling an endpoint directly.

Docs: https://developers.google.com/admob/android/ssv
"""
import base64
import json
import threading
import time
import urllib.request
from urllib.parse import parse_qs

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

VERIFIER_KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json"
KEYS_TTL_SECONDS = 24 * 3600

_cache = {"fetched_at": 0.0, "keys": {}}
_lock = threading.Lock()


class SsvError(Exception):
    pass


def _b64url_decode(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def fetch_verifier_keys():
    """Returns {key_id(int): PEM string} from Google."""
    with urllib.request.urlopen(VERIFIER_KEYS_URL, timeout=8) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return {int(k["keyId"]): k["pem"] for k in data["keys"]}


def _get_public_key(key_id: int, fetcher):
    with _lock:
        stale = time.time() - _cache["fetched_at"] > KEYS_TTL_SECONDS
        if stale or key_id not in _cache["keys"]:
            try:
                _cache["keys"] = fetcher()
                _cache["fetched_at"] = time.time()
            except Exception as exc:  # network failure
                if key_id not in _cache["keys"]:
                    raise SsvError(f"could not load verifier keys: {exc}")
        pem = _cache["keys"].get(key_id)
    if not pem:
        raise SsvError("unknown key_id")
    pem_bytes = pem.encode("utf-8") if isinstance(pem, str) else pem
    return serialization.load_pem_public_key(pem_bytes)


def verify_ssv_query(raw_query: bytes, fetcher=fetch_verifier_keys) -> dict:
    """
    Verifies the signature of a raw SSV query string and returns the params.
    Google signs everything before '&signature=' (signature and key_id are
    always the last two parameters).
    """
    marker = b"&signature="
    idx = raw_query.find(marker)
    if idx < 0:
        raise SsvError("missing signature")
    message = raw_query[:idx]
    params = {k: v[0] for k, v in parse_qs(raw_query.decode("utf-8")).items()}
    signature = params.get("signature")
    key_id = params.get("key_id")
    if not signature or not key_id:
        raise SsvError("missing signature or key_id")
    try:
        key = _get_public_key(int(key_id), fetcher)
        key.verify(_b64url_decode(signature), message, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        raise SsvError("bad signature")
    except (ValueError, TypeError):
        raise SsvError("malformed signature or key_id")
    return params


def reset_cache_for_tests():
    with _lock:
        _cache["fetched_at"] = 0.0
        _cache["keys"] = {}
