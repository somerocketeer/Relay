"""TOML helpers with compatibility fallbacks.

This module centralises TOML parsing so that Relay can operate on
environments where Python < 3.11 is available but the ``tomli`` package
has not been installed yet.  Callers should catch ``TomlMissingError``
to present a friendly, actionable message to users and abort the
operation gracefully.
"""

from __future__ import annotations

from typing import Any, BinaryIO

_ERROR_MESSAGE = (
    "Relay requires Python 3.11+ (tomllib) or the 'tomli' package. "
    "Install tomli with 'pip install --user tomli' or upgrade Python."
)


class TomlMissingError(RuntimeError):
    """Raised when neither tomllib nor tomli is available."""


_TOML_MODULE: Any | None = None


def _import_toml_module() -> Any:
    try:
        import tomllib  # type: ignore[import-not-found]

        return tomllib
    except ModuleNotFoundError:
        try:
            import tomli  # type: ignore[import]

            return tomli
        except ModuleNotFoundError as exc:  # pragma: no cover - environment dependent
            raise TomlMissingError(_ERROR_MESSAGE) from exc


def _toml_module() -> Any:
    global _TOML_MODULE
    if _TOML_MODULE is None:
        _TOML_MODULE = _import_toml_module()
    return _TOML_MODULE


def load_file(handle: BinaryIO) -> Any:
    """Load TOML content from a binary file handle."""

    return _toml_module().load(handle)


def loads(data: str | bytes) -> Any:
    """Load TOML content from a string or bytes payload."""

    module = _toml_module()
    if isinstance(data, bytes):
        return module.loads(data.decode("utf-8"))
    return module.loads(data)


def load_path(path: str) -> Any:
    """Load TOML content from a filesystem path."""

    with open(path, "rb") as handle:  # noqa: PTH123
        return load_file(handle)
