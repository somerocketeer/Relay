"""Shared helpers for Relay kit configuration and persona overlays."""
from __future__ import annotations

import json
import os
from typing import Dict, List, Tuple

from relay_toml import TomlMissingError, load_path as _load_toml_path


def _read_toml(path: str) -> Dict:
    if not os.path.isfile(path):
        return {}
    try:
        return _load_toml_path(path) or {}
    except TomlMissingError:
        raise


def _clean_string(value, *, default: str = "") -> str:
    if isinstance(value, str):
        stripped = value.strip()
        if stripped:
            return stripped
    return default


def _collect_persona_list(values) -> List[str]:
    result: List[str] = []
    if not values:
        return result
    for entry in values:
        if isinstance(entry, str):
            cleaned = entry.strip()
            if cleaned and cleaned not in result:
                result.append(cleaned)
    return result


def _normalize_pane(entry, default_dir: str) -> Dict:
    pane: Dict = {
        "run": "",
        "dir": "",
        "name": "",
        "personas": [],
    }
    if isinstance(entry, str):
        pane["run"] = entry.strip()
        pane["dir"] = default_dir
        return pane
    if not isinstance(entry, dict):
        return pane
    run_value = entry.get("run") or entry.get("cmd") or entry.get("command") or ""
    pane["run"] = _clean_string(run_value)
    pane["dir"] = _clean_string(entry.get("dir"), default=default_dir)
    pane["name"] = _clean_string(entry.get("name"))
    pane["personas"] = _collect_persona_list(entry.get("personas"))
    return pane


def _normalize_window(entry, default_dir: str, index: int) -> Dict:
    window_dir = _clean_string(entry.get("dir"), default=default_dir)
    panes_raw = entry.get("panes") or []
    panes: List[Dict] = []
    for idx, pane_entry in enumerate(panes_raw):
        normalized = _normalize_pane(pane_entry, window_dir)
        normalized["index"] = idx
        panes.append(normalized)
    return {
        "index": index,
        "name": _clean_string(entry.get("name"), default=f"window{index + 1}"),
        "layout": _clean_string(entry.get("layout")),
        "dir": window_dir,
        "panes": panes,
    }


def _commands_to_window(commands, default_dir: str) -> Dict:
    panes: List[Dict] = []
    for idx, command in enumerate(commands or []):
        normalized = _normalize_pane(command, default_dir)
        normalized["index"] = idx
        panes.append(normalized)
    return {
        "index": 0,
        "name": "main",
        "layout": "",
        "dir": default_dir,
        "panes": panes,
    }


def load_kit_config(kit_file: str, kit_dir: str) -> Dict:
    data = _read_toml(kit_file)
    session = _clean_string(data.get("session"), default=os.path.basename(kit_dir))
    workdir = _clean_string(data.get("dir"), default=kit_dir)
    attach = bool(data.get("attach", True))

    personas: List[str] = []
    single_persona = data.get("persona")
    if isinstance(single_persona, str):
        persona = single_persona.strip()
        if persona:
            personas.append(persona)
    personas.extend(_collect_persona_list(data.get("personas")))

    windows: List[Dict] = []
    windows_raw = data.get("windows")
    if isinstance(windows_raw, list) and windows_raw:
        for idx, entry in enumerate(windows_raw):
            if isinstance(entry, dict):
                windows.append(_normalize_window(entry, workdir, idx))
    else:
        commands = data.get("commands") or []
        if commands:
            windows.append(_commands_to_window(commands, workdir))

    return {
        "session": session or os.path.basename(kit_dir),
        "workdir": workdir or kit_dir,
        "attach": attach,
        "windows": windows,
        "kit_personas": personas,
    }


def pane_overlay_path(kit_dir: str) -> str:
    return os.path.join(kit_dir, "pane-personas.json")


def load_pane_overlays(kit_dir: str) -> Dict[str, List[str]]:
    path = pane_overlay_path(kit_dir)
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle) or {}
    except (json.JSONDecodeError, OSError):
        return {}
    panes = data.get("panes")
    if not isinstance(panes, dict):
        return {}
    overlays: Dict[str, List[str]] = {}
    for key, value in panes.items():
        if not isinstance(key, str):
            continue
        names = _collect_persona_list(value)
        if names:
            overlays[key] = names
    return overlays


def save_pane_overlays(kit_dir: str, overlays: Dict[str, List[str]]) -> str:
    path = pane_overlay_path(kit_dir)
    payload = {
        "version": 1,
        "panes": {key: value for key, value in overlays.items() if value},
    }
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return path


def overlay_key(window_index: int, pane_index: int) -> str:
    return f"{window_index}:{pane_index}"


def dedupe_personas(*persona_lists: Tuple[List[str], ...]) -> List[str]:
    seen: set = set()
    ordered: List[str] = []
    for persona_list in persona_lists:
        for name in persona_list or []:
            if name not in seen:
                ordered.append(name)
                seen.add(name)
    return ordered
