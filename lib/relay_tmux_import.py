"""Utilities to capture tmux sessions as Relay kits."""
from __future__ import annotations

import argparse
import datetime as _dt
import os
import re
import subprocess
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Sequence

_TMUX_SEPARATOR = "__RELAY_SEP__"


class TmuxError(RuntimeError):
    """Raised when tmux interaction fails."""


@dataclass
class PaneWarning:
    message: str
    suggestion: Optional[str] = None


@dataclass
class Pane:
    index: int
    pane_id: str
    path: str
    current_command: str
    start_command: str
    title: str
    width: int
    height: int
    display_command: str = ""
    annotations: List[str] = field(default_factory=list)
    warnings: List[PaneWarning] = field(default_factory=list)


@dataclass
class Window:
    index: int
    window_id: str
    name: str
    path: str
    layout: str
    panes: List[Pane]


@dataclass
class SessionSnapshot:
    session: str
    session_path: str
    windows: List[Window]


def _run_tmux(args: Sequence[str]) -> str:
    sock_name = os.environ.get("RELAY_TMUX_SOCKET_NAME")
    sock_path = os.environ.get("RELAY_TMUX_SOCKET")
    prefix: List[str] = ["tmux"]
    if sock_name:
        prefix.extend(["-L", sock_name])
    elif sock_path:
        prefix.extend(["-S", sock_path])
    result = subprocess.run(
        [*prefix, *args],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        cmd_str = "tmux " + " ".join(args)
        raise TmuxError(result.stderr.strip() or f"Command failed: {cmd_str}")
    return result.stdout.rstrip("\n")


def _parse_records(blob: str, expected_fields: int) -> Iterable[List[str]]:
    if not blob:
        return []
    rows: List[List[str]] = []
    for line in blob.splitlines():
        parts = line.split(_TMUX_SEPARATOR)
        if len(parts) != expected_fields:
            continue
        rows.append(parts)
    return rows


def _gather_session(session: str) -> SessionSnapshot:
    try:
        session_path = _run_tmux(["display-message", "-p", "-t", session, "#{session_path}"])
    except TmuxError:
        session_path = ""

    window_fmt = _TMUX_SEPARATOR.join(
        [
            "#{window_index}",
            "#{window_id}",
            "#{window_name}",
            "#{window_layout}",
            "#{window_active}",
            "#{window_panes}",
            "#{window_active_clients}",
        ]
    )
    window_blob = _run_tmux(["list-windows", "-t", session, "-F", window_fmt])
    windows: List[Window] = []

    for window_fields in _parse_records(window_blob, 7):
        index_str, window_id, name, layout, _, _, _ = window_fields
        try:
            index = int(index_str)
        except ValueError:
            continue
        pane_fmt = _TMUX_SEPARATOR.join(
            [
                "#{pane_index}",
                "#{pane_id}",
                "#{pane_current_path}",
                "#{pane_current_command}",
                "#{pane_start_command}",
                "#{pane_title}",
                "#{pane_width}",
                "#{pane_height}",
            ]
        )
        pane_blob = _run_tmux(["list-panes", "-t", window_id, "-F", pane_fmt])
        panes: List[Pane] = []
        for pane_fields in _parse_records(pane_blob, 8):
            (
                pane_index,
                pane_id,
                pane_path,
                pane_current_cmd,
                pane_start_cmd,
                pane_title,
                pane_w,
                pane_h,
            ) = pane_fields
            try:
                pane_idx = int(pane_index)
            except ValueError:
                continue
            try:
                width = int(pane_w)
            except ValueError:
                width = 0
            try:
                height = int(pane_h)
            except ValueError:
                height = 0
            panes.append(
                Pane(
                    index=pane_idx,
                    pane_id=pane_id,
                    path=pane_path,
                    current_command=pane_current_cmd.strip(),
                    start_command=pane_start_cmd.strip(),
                    title=pane_title.strip(),
                    width=width,
                    height=height,
                )
            )
        windows.append(
            Window(
                index=index,
                window_id=window_id,
                name=name.strip(),
                path=_run_tmux(
                    ["display-message", "-p", "-t", window_id, "#{window_active_path}"]
                ).strip(),
                layout=layout.strip(),
                panes=sorted(panes, key=lambda p: p.index),
            )
        )
    windows.sort(key=lambda w: w.index)
    return SessionSnapshot(session=session, session_path=session_path.strip(), windows=windows)


def _command_for_pane(pane: Pane) -> str:
    for candidate in (pane.start_command, pane.current_command, pane.title):
        if candidate:
            cleaned = " ".join(candidate.strip().split())
            if cleaned:
                return cleaned
    return "sh"


def _user_path(path: str) -> str:
    path = path.strip()
    if not path:
        return ""
    try:
        expanded = os.path.abspath(os.path.expanduser(path))
    except OSError:
        expanded = os.path.expanduser(path)
    home = os.path.expanduser("~")
    if expanded == home:
        return "~"
    if expanded.startswith(home + os.sep):
        rel = os.path.relpath(expanded, home)
        return f"~/{rel}" if rel != "." else "~"
    return expanded


def _escape_toml(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\t", "\\t")
        .replace("\r", "\\r")
        .replace("\n", "\\n")
    )
    return f'"{escaped}"'


def _classify_command(command: str) -> Optional[str]:
    lowered = command.strip().lower()
    if not lowered:
        return None
    if lowered in {"sh", "bash", "zsh", "fish"}:
        return "Shell: review history for common tasks"
    if lowered.startswith(("npm run", "yarn", "pnpm")):
        return "Dev server"
    if lowered.startswith("tail") or "journalctl" in lowered:
        return "Log monitor"
    if lowered.startswith("kubectl logs"):
        return "Kubernetes logs"
    if lowered.startswith("nvim") or lowered.startswith("vim") or lowered.startswith("emacs"):
        return "Editor"
    if lowered.startswith("htop"):
        return "Process monitor"
    return None


_KUBECTL_POD_RE = re.compile(r"kubectl\s+logs[^\n]*\bpod/([\w.-]+)")
_IP_RE = re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")
_INLINE_SECRET_RE = re.compile(r"\b(?:DATABASE_URL|PGURI|MYSQL_URL|AMQP_URL)=[^\s]+", re.IGNORECASE)
_URL_CREDENTIAL_RE = re.compile(r"://[^\s/:]+:[^\s@]+@")


def _suggest_command(command: str, match: re.Match) -> Optional[str]:
    pod_name = match.group(1)
    base = pod_name.split("-", 1)[0]
    if base and base != pod_name:
        return command.replace(f"pod/{pod_name}", f"deployment/{base}")
    return None


def _collect_warnings(pane: Pane) -> None:
    command = pane.display_command
    if not command:
        return
    kubectl_match = _KUBECTL_POD_RE.search(command)
    if kubectl_match:
        suggestion = _suggest_command(command, kubectl_match)
        message = (
            "Pod name '" + kubectl_match.group(1) + "' is likely ephemeral; consider using a selector"
        )
        pane.warnings.append(PaneWarning(message=message, suggestion=suggestion))
    if _URL_CREDENTIAL_RE.search(command) or _INLINE_SECRET_RE.search(command):
        pane.warnings.append(
            PaneWarning(
                message="Command contains inline credentials; move secrets to a persona or env var",
                suggestion=None,
            )
        )
    for match in _IP_RE.finditer(command):
        ip = match.group(0)
        if ip.startswith("127.") or ip == "0.0.0.0":
            continue
        pane.warnings.append(
            PaneWarning(
                message=f"Hard-coded address '{ip}' detected; confirm it is stable",
                suggestion=None,
            )
        )


def _render_windows(windows: Sequence[Window], base_dir: str) -> List[str]:
    lines: List[str] = []
    for window in windows:
        lines.append("")
        lines.append("[[windows]]")
        name = window.name or f"window{window.index + 1}"
        lines.append(f"name = {_escape_toml(name)}")
        window_dir = window.path or base_dir
        lines.append(f"dir = {_escape_toml(_user_path(window_dir) if window_dir else base_dir)}")
        if window.layout:
            lines.append(f"layout = {_escape_toml(window.layout)}")
        for pane in window.panes:
            lines.append("")
            pane_title = f"Pane {pane.index}: {pane.display_command}"
            lines.append(f"# {pane_title}")
            label = _classify_command(pane.display_command)
            if label:
                lines.append(f"# {label}")
            for warn in pane.warnings:
                lines.append(f"# WARNING: {warn.message}")
            lines.append("[[windows.panes]]")
            lines.append(f"run = {_escape_toml(pane.display_command)}")
            pane_dir = pane.path or window_dir or base_dir
            lines.append(f"dir = {_escape_toml(_user_path(pane_dir))}")
    return lines


def _render_warnings_block(warnings: Iterable[PaneWarning]) -> List[str]:
    collected = [warn.message for warn in warnings if warn.message]
    if not collected:
        return []
    lines = ["", "[import_warnings]", "warnings = ["]
    for warning in collected:
        lines.append(f"  {_escape_toml(warning)},")
    lines.append("]")
    lines.append("reviewed = false")
    return lines


def build_kit(snapshot: SessionSnapshot, *, kit_name: str, interactive: bool = False) -> Dict[str, object]:
    base_dir = snapshot.session_path
    if not base_dir:
        for window in snapshot.windows:
            if window.path:
                base_dir = window.path
                break
    if not base_dir and snapshot.windows:
        for pane in snapshot.windows[0].panes:
            if pane.path:
                base_dir = pane.path
                break
    if not base_dir:
        base_dir = os.path.expanduser("~")

    for window in snapshot.windows:
        for pane in window.panes:
            pane.display_command = _command_for_pane(pane)
            pane.warnings = []
            _collect_warnings(pane)

    if interactive:
        for window in snapshot.windows:
            for pane in window.panes:
                while True:
                    notable = [warn for warn in pane.warnings if warn.suggestion]
                    if not notable:
                        break
                    warn = notable[0]
                    prompt = (
                        f"{warn.message}\nApply suggested command? [{warn.suggestion}] (Y/n/edit): "
                    )
                    try:
                        answer = input(prompt).strip().lower()
                    except EOFError:
                        answer = "n"
                    if answer in ("", "y", "yes") and warn.suggestion:
                        pane.display_command = warn.suggestion
                    elif answer in ("e", "edit"):
                        try:
                            replacement = input("Enter replacement command: ").strip()
                        except EOFError:
                            replacement = ""
                        if replacement:
                            pane.display_command = replacement
                    else:
                        break
                    pane.display_command = " ".join(pane.display_command.split())
                    pane.warnings = []
                    _collect_warnings(pane)

    stamp = _dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S %Z")
    header_comment = f"# Generated from tmux session '{snapshot.session}' on {stamp}".rstrip()
    review_comment = "# REVIEW BEFORE USE: Commands are snapshots; confirm they are repeatable"
    kit_lines = [header_comment, review_comment, "", "version = 1"]
    session_comment = ""
    if kit_name != snapshot.session:
        session_comment = f"  # renamed from {snapshot.session}"
    kit_lines.append(f"session = {_escape_toml(kit_name)}{session_comment}")
    kit_lines.append(f"dir = {_escape_toml(_user_path(base_dir))}")
    kit_lines.append("attach = true")
    kit_lines.append("backend = \"tmux\"")

    window_lines = _render_windows(snapshot.windows, _user_path(base_dir))
    kit_lines.extend(window_lines)

    warnings_flat = [warn for window in snapshot.windows for pane in window.panes for warn in pane.warnings]
    kit_lines.extend(_render_warnings_block(warnings_flat))
    kit_lines.append("")

    return {
        "kit_text": "\n".join(kit_lines),
        "warnings": warnings_flat,
    }


def import_session(
    session: str,
    *,
    kit_name: str,
    interactive: bool = False,
) -> Dict[str, object]:
    snapshot = _gather_session(session)
    return build_kit(snapshot, kit_name=kit_name, interactive=interactive)


def _write_file(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text)


def _write_warnings(path: str, warnings: Sequence[PaneWarning]) -> None:
    if not warnings:
        return
    with open(path, "w", encoding="utf-8") as handle:
        for warn in warnings:
            handle.write(warn.message)
            handle.write("\n")


def main(argv: Optional[Sequence[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Convert tmux session to Relay kit")
    parser.add_argument("session", help="tmux session to import")
    parser.add_argument("kit_name", help="Name to use inside kit.toml")
    parser.add_argument("--output", help="Path to write kit.toml (omit for stdout)")
    parser.add_argument("--warnings", help="Write warnings to a log file")
    parser.add_argument("--interactive", action="store_true", help="Prompt for suggested fixes")
    args = parser.parse_args(argv)

    result = import_session(args.session, kit_name=args.kit_name, interactive=args.interactive)
    kit_text = result["kit_text"]
    warnings = result["warnings"]

    if args.output:
        _write_file(args.output, kit_text)
    else:
        print(kit_text)

    if args.warnings:
        _write_warnings(args.warnings, warnings)

    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
