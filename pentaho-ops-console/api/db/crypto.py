"""
Fernet-based symmetric encryption helpers for secrets at rest.

If OPS_ENCRYPTION_KEY is not set, secrets are stored as plaintext and a
one-time warning is emitted.  This lets the app start without configuration
while making it easy to add encryption later by setting the env var.
"""

from __future__ import annotations
import logging

from ..config import ENCRYPTION_KEY

logger = logging.getLogger(__name__)

_warned = False
_fernet = None

def _get_fernet():
    global _fernet, _warned
    if _fernet is not None:
        return _fernet
    if not ENCRYPTION_KEY:
        if not _warned:
            logger.warning(
                "OPS_ENCRYPTION_KEY is not set — secrets will be stored as "
                "plaintext. Set this env var and re-save secrets to encrypt them."
            )
            _warned = True
        return None
    try:
        from cryptography.fernet import Fernet
        _fernet = Fernet(ENCRYPTION_KEY.encode())
        return _fernet
    except Exception as exc:
        logger.error("Failed to initialise Fernet: %s", exc)
        return None


def encrypt(plaintext: str) -> str:
    """Encrypt *plaintext* and return a string suitable for DB storage.

    Falls back to plaintext if encryption is not configured.
    """
    f = _get_fernet()
    if f is None:
        return plaintext
    return f.encrypt(plaintext.encode()).decode()


def decrypt(stored: str) -> str:
    """Decrypt a value previously returned by :func:`encrypt`.

    Handles both encrypted tokens and raw plaintext gracefully.
    """
    f = _get_fernet()
    if f is None:
        return stored
    try:
        return f.decrypt(stored.encode()).decode()
    except Exception:
        # Value was stored as plaintext before encryption was enabled
        return stored
