#!/usr/bin/env python3
"""
whisper-ptt — Dual foot-pedal push-to-talk transcription daemon.

Grabs a USB foot pedal via evdev (preventing raw a/b from leaking),
records audio while held, transcribes (faster-whisper or whisper-cli),
and types the result into the focused window.

Left pedal:  quick    — greedy decode, no post-processing
Right pedal: accurate — beam search + VAD + temperature fallback

Both pedals use the same model. The difference is decode parameters.

Usage:
    python ptt.py --setup       detect pedals interactively
    python ptt.py --list        show all input devices
    python ptt.py               run daemon
    python ptt.py --backend whisper-cli --whisper-cli /path/to/whisper-cli --whisper-model /path/to/ggml-model.bin
    python ptt.py --backend whisper-server
    python ptt.py --test-mic    record 3s and play back (verify mic)
"""

from __future__ import annotations

import argparse
import asyncio
import errno
import json
import os
import select
import signal
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

CFG_DIR = Path.home() / ".config" / "whisper-ptt"
CFG_FILE = CFG_DIR / "config.json"

DEFAULTS: dict = {
    "backend": "faster-whisper",  # faster-whisper | whisper-cli | whisper-server
    "model": "large-v3",
    "language": "en",
    "device_name": "",
    "device_path": "",
    "left_key": "KEY_A",
    "right_key": "KEY_B",
    "device": "auto",           # auto | cpu | cuda
    "compute_type": "float16",   # float16 (GPU) | int8 (CPU)
    "cpu_threads": 0,             # 0 = auto
    "local_files_only": True,     # avoid HF checks once model is cached
    "sample_rate": 16000,
    "typer": "auto",             # auto | wtype | ydotool | xdotool
    "ydotool_key_delay_ms": 0,
    "output_mode": "type",       # type | paste | auto
    "paste_method": "auto",      # auto | ydotool | xdotool
    "paste_min_chars": 24,
    "output_timeout_s": 8,
    "submit_on_accurate": False,
    "submit_typer": "auto",      # auto | wtype | ydotool | xdotool
    "submit_delay_ms": 0,
    "submit_timeout_s": 5,
    "exclusive_grab": True,
    # whisper-cli (whisper.cpp) backend settings
    "whisper_cli": "",
    "whisper_model_path": "",
    "whisper_threads": 0,
    "whisper_gpu": True,
    "whisper_gpu_device": 0,
    # persistent whisper-server backend settings
    "whisper_server_url": "http://127.0.0.1:8178/inference",
    "whisper_server_health_url": "http://127.0.0.1:8178/health",
    "whisper_server_request_timeout": 120,
    "whisper_server_startup_wait": 45,
    "whisper_server_accurate_vad": False,
    # cold-start mitigation
    "warmup_on_start": True,
    "warmup_mode": "quick",      # quick | accurate
    "warmup_clip_seconds": 0.6,
}

# Greedy decode — fast, no post-processing
QUICK: dict = {
    "beam_size": 1,
    "temperature": 0.0,
    "vad_filter": False,
    "condition_on_previous_text": False,
    "without_timestamps": True,
}

# Beam search + VAD + temperature fallback — slower, more accurate
ACCURATE: dict = {
    # Tuned for much lower latency on CPU while still applying
    # a stronger decode path than QUICK.
    "beam_size": 3,
    "temperature": [0.0, 0.2, 0.4],
    "vad_filter": True,
    "vad_parameters": {"min_silence_duration_ms": 500},
    "condition_on_previous_text": True,
    "without_timestamps": True,
}


def is_cuda_error(exc: Exception) -> bool:
    """Best-effort detection of missing CUDA runtime/libs."""
    msg = str(exc).lower()
    needles = (
        "libcublas",
        "libcudnn",
        "libcuda",
        "cuda",
        "cublas",
        "cudnn",
    )
    return any(n in msg for n in needles)


def load_cfg() -> dict:
    c = dict(DEFAULTS)
    if CFG_FILE.exists():
        c.update(json.loads(CFG_FILE.read_text()))
    return c


def save_cfg(c: dict) -> None:
    CFG_DIR.mkdir(parents=True, exist_ok=True)
    CFG_FILE.write_text(json.dumps(c, indent=2) + "\n")
    print(f"  saved: {CFG_FILE}")


# ---------------------------------------------------------------------------
# Device helpers
# ---------------------------------------------------------------------------

def cmd_list() -> None:
    """List all evdev input devices."""
    import evdev
    from evdev import InputDevice, ecodes

    print("\nInput devices:\n")
    for path in sorted(evdev.list_devices()):
        try:
            dev = InputDevice(path)
        except PermissionError:
            print(f"  {path}  (permission denied)")
            continue
        caps = dev.capabilities(verbose=False)
        keys = caps.get(ecodes.EV_KEY, [])
        print(f"  {path}")
        print(f"    name:  {dev.name}")
        print(f"    keys:  {len(keys)}")
        if len(keys) <= 12:
            names = []
            for k in keys:
                n = ecodes.KEY.get(k, k)
                if isinstance(n, list):
                    n = n[0]
                names.append(str(n))
            print(f"    codes: {', '.join(names)}")
        print()


def _open_all_devices() -> dict[int, "evdev.InputDevice"]:
    """Open all accessible evdev devices, return {fd: device}."""
    import evdev
    from evdev import InputDevice

    devices: dict = {}
    for p in sorted(evdev.list_devices()):
        try:
            d = InputDevice(p)
            devices[d.fd] = d
        except PermissionError:
            continue
    return devices


def _wait_for_keypress(devices: dict, prompt: str):
    """Block until a key-down event on any device. Return (device, key_name)."""
    from evdev import ecodes

    print(prompt)
    while True:
        r, _, _ = select.select(list(devices.keys()), [], [], 0.5)
        for fd in r:
            dev = devices[fd]
            while True:
                ev = dev.read_one()
                if ev is None:
                    break
                if ev.type == ecodes.EV_KEY and ev.value == 1:
                    k = ecodes.KEY.get(ev.code, ev.code)
                    if isinstance(k, list):
                        k = k[0]
                    return dev, str(k)


def _drain_events(devices: dict) -> None:
    """Drain any queued events from all devices."""
    time.sleep(0.3)
    for d in devices.values():
        while d.read_one() is not None:
            pass


def cmd_setup() -> None:
    """Interactive pedal detection — press each pedal when prompted."""
    devices = _open_all_devices()
    if not devices:
        print("  no accessible input devices")
        print("  check: sudo usermod -aG input $USER  (then re-login)")
        sys.exit(1)

    print("\n  Pedal setup\n")

    dev_l, key_l = _wait_for_keypress(devices, "  Press LEFT pedal...")
    print(f"    device: {dev_l.name}")
    print(f"    path:   {dev_l.path}")
    print(f"    key:    {key_l}\n")

    _drain_events(devices)

    dev_r, key_r = _wait_for_keypress(devices, "  Press RIGHT pedal...")
    print(f"    device: {dev_r.name}")
    print(f"    path:   {dev_r.path}")
    print(f"    key:    {key_r}\n")

    for d in devices.values():
        d.close()

    cfg = load_cfg()
    cfg["device_name"] = dev_l.name
    cfg["device_path"] = dev_l.path
    cfg["left_key"] = key_l
    cfg["right_key"] = key_r
    save_cfg(cfg)

    if dev_l.path != dev_r.path:
        print(f"  note: pedals detected on different evdev devices")
        print(f"    left:  {dev_l.path}")
        print(f"    right: {dev_r.path}")
        print(f"  using left device path — both pedals should be on the same device\n")

    print("  done. run:  python ptt.py\n")


def find_device(cfg: dict):
    """Find pedal by name (stable across reboots), fall back to path."""
    import evdev
    from evdev import InputDevice

    name = cfg.get("device_name", "")
    if name:
        for p in sorted(evdev.list_devices()):
            try:
                d = InputDevice(p)
                if d.name == name:
                    return d
            except PermissionError:
                continue

    path = cfg.get("device_path", "")
    if path:
        try:
            return InputDevice(path)
        except (FileNotFoundError, PermissionError):
            pass

    return None


# ---------------------------------------------------------------------------
# Mic test
# ---------------------------------------------------------------------------

def cmd_test_mic() -> None:
    """Record 3 seconds from the default mic and play it back."""
    import numpy as np
    import sounddevice as sd

    rate = 16000
    duration = 3
    print(f"\n  Recording {duration}s from default mic...")
    audio = sd.rec(int(duration * rate), samplerate=rate, channels=1, dtype="float32")
    sd.wait()
    peak = float(np.max(np.abs(audio)))
    print(f"  peak amplitude: {peak:.4f}")
    if peak < 0.01:
        print("  warning: very quiet — check mic selection / levels")
    print("  Playing back...")
    sd.play(audio, samplerate=rate)
    sd.wait()
    print("  done\n")


# ---------------------------------------------------------------------------
# Audio recorder (callback-based, non-blocking)
# ---------------------------------------------------------------------------

class Recorder:
    def __init__(self, rate: int = 16000):
        self.rate = rate
        self._chunks: list = []
        self._stream = None

    def start(self) -> None:
        import sounddevice as sd

        self._chunks = []
        self._stream = sd.InputStream(
            samplerate=self.rate,
            channels=1,
            dtype="float32",
            callback=self._cb,
        )
        self._stream.start()

    def stop(self):
        import numpy as np

        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        if self._chunks:
            return np.concatenate(self._chunks).flatten()
        return np.array([], dtype="float32")

    def _cb(self, data, frames, t, status) -> None:
        self._chunks.append(data.copy())


# ---------------------------------------------------------------------------
# Output: type text + notifications
# ---------------------------------------------------------------------------

def _run_cmd(
    cmd: list[str],
    text_input: str | None = None,
    timeout_s: float = 8.0,
) -> tuple[bool, str]:
    try:
        p = subprocess.run(
            cmd,
            input=text_input,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=max(0.5, float(timeout_s)),
        )
    except subprocess.TimeoutExpired:
        return False, f"timeout after {timeout_s:.1f}s"
    except Exception as e:
        return False, str(e)

    if p.returncode == 0:
        return True, ""
    msg = (p.stderr or p.stdout or f"exit {p.returncode}").strip()
    return False, msg


def _type_wtype(text: str) -> tuple[bool, str]:
    if not shutil.which("wtype"):
        return False, "wtype not found"
    timeout_s = max(3.0, min(20.0, 2.0 + len(text) / 100.0))
    return _run_cmd(["wtype", "--", text], timeout_s=timeout_s)


def _type_ydotool(text: str, key_delay_ms: int = 0) -> tuple[bool, str]:
    if not shutil.which("ydotool"):
        return False, "ydotool not found"

    kd = max(0, min(int(key_delay_ms), 50))
    base_per_char = 0.015 + (kd / 1000.0)
    timeout_s = max(4.0, min(90.0, 2.0 + (len(text) * base_per_char * 2.0)))

    ok, msg = _run_cmd(["ydotool", "type", "-d", str(kd), "--", text], timeout_s=timeout_s)
    if ok:
        return True, ""

    # Fallback for older builds that do not handle "--".
    ok2, msg2 = _run_cmd(["ydotool", "type", "-d", str(kd), text], timeout_s=timeout_s)
    if ok2:
        return True, ""
    return False, msg2 or msg


def _type_xdotool(text: str) -> tuple[bool, str]:
    if not shutil.which("xdotool"):
        return False, "xdotool not found"
    timeout_s = max(3.0, min(30.0, 2.0 + len(text) / 80.0))
    return _run_cmd(["xdotool", "type", "--delay", "1", "--", text], timeout_s=timeout_s)


def _enter_wtype() -> tuple[bool, str]:
    if not shutil.which("wtype"):
        return False, "wtype not found"
    return _run_cmd(["wtype", "-k", "Return"], timeout_s=3.0)


def _enter_ydotool() -> tuple[bool, str]:
    if not shutil.which("ydotool"):
        return False, "ydotool not found"
    return _run_cmd(["ydotool", "key", "28:1", "28:0"], timeout_s=3.0)


def _enter_xdotool() -> tuple[bool, str]:
    if not shutil.which("xdotool"):
        return False, "xdotool not found"
    return _run_cmd(["xdotool", "key", "--clearmodifiers", "Return"], timeout_s=3.0)


def submit_enter(submit_typer: str = "auto") -> tuple[bool, str]:
    methods = {
        "wtype": _enter_wtype,
        "ydotool": _enter_ydotool,
        "xdotool": _enter_xdotool,
    }

    mode = str(submit_typer or "auto").strip().lower()
    if mode == "auto":
        if os.environ.get("WAYLAND_DISPLAY"):
            order = ["ydotool", "wtype", "xdotool"]
        else:
            order = ["xdotool", "ydotool", "wtype"]
    else:
        order = [mode]

    errors: list[str] = []
    for name in order:
        fn = methods.get(name)
        if not fn:
            continue
        ok, msg = fn()
        if ok:
            return True, f"enter via {name}"
        if msg:
            errors.append(f"{name}: {msg}")

    detail = "; ".join(errors[:3]) if errors else "unknown submit error"
    return False, f"submit failed; {detail}"


def _paste_ydotool() -> tuple[bool, str]:
    if not shutil.which("ydotool"):
        return False, "ydotool not found"

    # Try Ctrl+V, then Shift+Insert.
    combos = [
        (["29:1", "47:1", "47:0", "29:0"], "ctrl+v"),
        (["42:1", "110:1", "110:0", "42:0"], "shift+insert"),
    ]

    errors: list[str] = []
    for seq, label in combos:
        ok, msg = _run_cmd(["ydotool", "key", *seq], timeout_s=3.0)
        if ok:
            return True, label
        if msg:
            errors.append(msg)

    detail = "; ".join(errors[-2:]) if errors else "ydotool paste failed"
    return False, detail


def _paste_xdotool() -> tuple[bool, str]:
    if not shutil.which("xdotool"):
        return False, "xdotool not found"

    ok, msg = _run_cmd(["xdotool", "key", "--clearmodifiers", "ctrl+v"], timeout_s=3.0)
    if ok:
        return True, "ctrl+v"

    ok2, msg2 = _run_cmd(
        ["xdotool", "key", "--clearmodifiers", "Shift+Insert"],
        timeout_s=3.0,
    )
    if ok2:
        return True, "shift+insert"

    return False, msg2 or msg


def _copy_clipboard(text: str) -> tuple[bool, str]:
    if shutil.which("wl-copy"):
        ok, msg = _run_cmd(["wl-copy"], text_input=text, timeout_s=4.0)
        if ok:
            return True, "copied to clipboard with wl-copy"
    if shutil.which("xclip"):
        ok, msg = _run_cmd(
            ["xclip", "-selection", "clipboard"],
            text_input=text,
            timeout_s=4.0,
        )
        if ok:
            return True, "copied to clipboard with xclip"
    return False, "no clipboard tool found (need wl-copy or xclip)"


def type_text(text: str, typer: str = "auto", ydotool_key_delay_ms: int = 0) -> tuple[bool, str]:
    if not text:
        return True, "empty"

    methods = {
        "wtype": _type_wtype,
        "ydotool": lambda s: _type_ydotool(s, ydotool_key_delay_ms),
        "xdotool": _type_xdotool,
    }

    if typer == "auto":
        if os.environ.get("WAYLAND_DISPLAY"):
            desktop = " ".join(
                [
                    os.environ.get("XDG_CURRENT_DESKTOP", ""),
                    os.environ.get("XDG_SESSION_DESKTOP", ""),
                ]
            ).lower()
            likely_wlroots = bool(
                os.environ.get("SWAYSOCK")
                or os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
                or "wlroots" in desktop
            )
            if likely_wlroots:
                order = ["wtype", "ydotool", "xdotool"]
            else:
                order = ["ydotool", "wtype", "xdotool"]
        else:
            order = ["xdotool", "ydotool", "wtype"]
    else:
        order = [typer]

    errors: list[str] = []
    for name in order:
        fn = methods.get(name)
        if not fn:
            continue
        ok, msg = fn(text)
        if ok:
            return True, f"typed via {name}"
        if msg:
            errors.append(f"{name}: {msg}")

    # Clipboard fallback is only used in auto mode to avoid side effects
    # when the user explicitly selected a typer.
    if typer == "auto":
        ok, msg = _copy_clipboard(text)
        if ok:
            return False, f"typing failed; {msg}"

    detail = "; ".join(errors[:3]) if errors else "unknown typing error"
    return False, f"typing failed; {detail}"


def paste_text(text: str, paste_method: str = "auto") -> tuple[bool, str]:
    if not text:
        return True, "empty"

    ok, copy_msg = _copy_clipboard(text)
    if not ok:
        return False, copy_msg

    methods = {
        "ydotool": _paste_ydotool,
        "xdotool": _paste_xdotool,
    }

    if paste_method == "auto":
        if os.environ.get("WAYLAND_DISPLAY"):
            order = ["ydotool", "xdotool"]
        else:
            order = ["xdotool", "ydotool"]
    else:
        order = [paste_method] + [m for m in ("ydotool", "xdotool") if m != paste_method]

    errors: list[str] = []
    for name in order:
        fn = methods.get(name)
        if not fn:
            continue
        ok, msg = fn()
        if ok:
            return True, f"pasted via {name} ({msg}; {copy_msg})"
        if msg:
            errors.append(f"{name}: {msg}")

    detail = "; ".join(errors[-2:]) if errors else "unknown paste error"
    return False, f"paste failed; {detail}"


def output_text(
    text: str,
    output_mode: str = "type",
    typer: str = "auto",
    ydotool_key_delay_ms: int = 0,
    paste_method: str = "auto",
    paste_min_chars: int = 24,
) -> tuple[bool, str]:
    mode = str(output_mode or "type").strip().lower()
    if mode not in ("type", "paste", "auto"):
        mode = "type"

    if mode == "type":
        return type_text(text, typer, ydotool_key_delay_ms)

    if mode == "paste":
        return paste_text(text, paste_method)

    threshold = max(0, int(paste_min_chars or 0))
    if len(text) >= threshold:
        ok, msg = paste_text(text, paste_method)
        if ok:
            return True, msg

        ok2, msg2 = type_text(text, typer, ydotool_key_delay_ms)
        if ok2:
            return True, f"{msg}; fallback {msg2}"
        return False, f"{msg}; fallback {msg2}"

    return type_text(text, typer, ydotool_key_delay_ms)


def notify(title: str, body: str = "") -> None:
    subprocess.Popen(
        ["notify-send", "--app-name=whisper-ptt", title, body],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


# ---------------------------------------------------------------------------
# Transcription
# ---------------------------------------------------------------------------

def _normalize_text(s: str) -> str:
    return " ".join(s.replace("\n", " ").split()).strip()


def transcribe(model, audio, params: dict, language: str) -> str:
    segments, _ = model.transcribe(audio, language=language, **params)
    return " ".join(s.text.strip() for s in segments).strip()


def find_whisper_cli(cfg: dict) -> str:
    if cfg.get("whisper_cli"):
        p = Path(cfg["whisper_cli"]).expanduser()
        if p.exists() and os.access(p, os.X_OK):
            return str(p)

    for name in ("whisper-cli", "whisper-cpp"):
        p = shutil.which(name)
        if p:
            return p

    raise FileNotFoundError(
        "whisper-cli not found in PATH. Install whisper.cpp with Vulkan/ROCm support."
    )


def find_whisper_model(cfg: dict) -> str:
    if cfg.get("whisper_model_path"):
        p = Path(cfg["whisper_model_path"]).expanduser()
        if p.exists():
            return str(p)
        raise FileNotFoundError(f"whisper model not found: {p}")

    search_dirs = [
        Path("/usr/share/whisper.cpp/models"),
        Path("/usr/local/share/whisper.cpp/models"),
        Path.home() / ".local" / "share" / "whisper.cpp" / "models",
        Path.home() / ".cache" / "whisper.cpp",
    ]
    preferred = [
        "ggml-large-v3-turbo.bin",
        "ggml-large-v3.bin",
        "ggml-medium.en.bin",
        "ggml-small.en.bin",
        "ggml-base.en.bin",
    ]

    for d in search_dirs:
        for name in preferred:
            p = d / name
            if p.exists():
                return str(p)

    raise FileNotFoundError(
        "No whisper.cpp model found. Set 'whisper_model_path' in config.json."
    )


def write_wav_16k_mono(path: Path, audio) -> None:
    import numpy as np
    import wave

    clipped = np.clip(audio, -1.0, 1.0)
    pcm16 = (clipped * 32767.0).astype(np.int16)

    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(16000)
        wf.writeframes(pcm16.tobytes())


def transcribe_whisper_cli(audio, mode: str, cfg: dict, cli_path: str, model_path: str) -> str:
    threads = int(cfg.get("whisper_threads", 0) or 0)
    if threads <= 0:
        cores = os.cpu_count() or 4
        threads = max(4, cores - 2)

    with tempfile.TemporaryDirectory(prefix="whisper-ptt-") as td:
        td_path = Path(td)
        wav_path = td_path / "input.wav"
        out_base = td_path / "out"
        out_txt = td_path / "out.txt"

        write_wav_16k_mono(wav_path, audio)

        cmd = [
            cli_path,
            "-f", str(wav_path),
            "-m", model_path,
            "-l", cfg.get("language", "en"),
            "-t", str(threads),
            "-nt",
            "-np",
            "-otxt",
            "-of", str(out_base),
            "-tp", "0.0",
        ]

        if cfg.get("whisper_gpu", True):
            cmd += ["-dev", str(int(cfg.get("whisper_gpu_device", 0) or 0))]
            cmd += ["-fa"]
        else:
            cmd += ["-ng"]

        if mode == "quick":
            cmd += ["-bs", "1", "-bo", "1", "-nf", "-tpi", "0.0"]
        else:
            cmd += ["-bs", "4", "-bo", "2", "-tpi", "0.2"]

        p = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if p.returncode != 0:
            detail = (p.stderr or p.stdout or f"exit {p.returncode}").strip()
            raise RuntimeError(f"whisper-cli failed: {detail}")

        if out_txt.exists():
            return _normalize_text(out_txt.read_text(errors="ignore"))

        # fallback: some builds may only print to stdout
        return _normalize_text(p.stdout)


def _multipart_form_data(fields: dict[str, str], file_field: str, file_path: Path) -> tuple[bytes, str]:
    boundary = f"----whisperptt-{uuid.uuid4().hex}"
    b = bytearray()

    for k, v in fields.items():
        b.extend(f"--{boundary}\r\n".encode())
        b.extend(f'Content-Disposition: form-data; name="{k}"\r\n\r\n'.encode())
        b.extend(str(v).encode())
        b.extend(b"\r\n")

    data = file_path.read_bytes()
    b.extend(f"--{boundary}\r\n".encode())
    b.extend(
        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_path.name}"\r\n'.encode()
    )
    b.extend(b"Content-Type: audio/wav\r\n\r\n")
    b.extend(data)
    b.extend(b"\r\n")
    b.extend(f"--{boundary}--\r\n".encode())

    return bytes(b), f"multipart/form-data; boundary={boundary}"


def _server_ready(health_url: str, timeout: float = 2.0) -> bool:
    try:
        req = urllib.request.Request(health_url, method="GET")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status == 200
    except Exception:
        return False


def wait_for_server(health_url: str, startup_wait: int) -> bool:
    deadline = time.time() + startup_wait
    while time.time() < deadline:
        if _server_ready(health_url, timeout=2.0):
            return True
        time.sleep(0.5)
    return False


def transcribe_whisper_server(audio, mode: str, cfg: dict) -> str:
    server_url = cfg.get("whisper_server_url", DEFAULTS["whisper_server_url"])
    timeout = int(cfg.get("whisper_server_request_timeout", 120))

    with tempfile.TemporaryDirectory(prefix="whisper-ptt-") as td:
        td_path = Path(td)
        wav_path = td_path / "input.wav"
        write_wav_16k_mono(wav_path, audio)

        fields: dict[str, str] = {
            "language": cfg.get("language", "en"),
            "response_format": "json",
            "no_timestamps": "true",
            "temperature": "0.0",
        }

        if mode == "quick":
            fields.update(
                {
                    "beam_size": "1",
                    "best_of": "1",
                    "temperature_inc": "0.0",
                    "vad": "false",
                }
            )
        else:
            use_vad = bool(cfg.get("whisper_server_accurate_vad", False))
            fields.update(
                {
                    "beam_size": "4",
                    "best_of": "2",
                    "temperature_inc": "0.2",
                    "vad": "true" if use_vad else "false",
                }
            )
            if use_vad:
                fields["vad_min_silence_duration_ms"] = "500"

        body, content_type = _multipart_form_data(fields, "file", wav_path)
        req = urllib.request.Request(
            server_url,
            data=body,
            method="POST",
            headers={"Content-Type": content_type},
        )

        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"whisper-server HTTP {e.code}: {detail}")
        except urllib.error.URLError as e:
            raise RuntimeError(f"whisper-server unavailable: {e}")

        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            return _normalize_text(raw)

        if isinstance(payload, dict):
            txt = payload.get("text", "")
            return _normalize_text(str(txt))

        return ""


def run_warmup_if_enabled(cfg: dict, backend: str, model, cli_path: str, model_path: str) -> None:
    if not cfg.get("warmup_on_start", True):
        return

    mode = str(cfg.get("warmup_mode", "quick")).strip().lower()
    if mode not in ("quick", "accurate"):
        mode = "quick"

    secs = float(cfg.get("warmup_clip_seconds", 0.6) or 0.6)
    secs = max(0.2, min(secs, 2.0))

    import numpy as np

    samples = int(16000 * secs)
    silent = np.zeros(samples, dtype=np.float32)

    t0 = time.time()
    try:
        if backend == "whisper-server":
            _ = transcribe_whisper_server(silent, mode, cfg)
        elif backend == "whisper-cli":
            _ = transcribe_whisper_cli(silent, mode, cfg, cli_path, model_path)
        elif backend == "faster-whisper":
            params = QUICK if mode == "quick" else ACCURATE
            _ = transcribe(model, silent, params, cfg.get("language", "en"))
        else:
            return
        elapsed = time.time() - t0
        print(f"  warmup:  ok ({elapsed:.1f}s)")
    except Exception as e:
        print(f"  warmup:  skipped ({e})")


# ---------------------------------------------------------------------------
# Daemon
# ---------------------------------------------------------------------------

async def run(cfg: dict) -> None:
    from evdev import ecodes
    backend = str(cfg.get("backend", "faster-whisper")).strip().lower()
    loop = asyncio.get_event_loop()

    # backend state
    model = None
    runtime_device = "cpu"
    compute = "int8"
    cpu_threads = int(cfg.get("cpu_threads", 0) or 0)
    local_files_only = bool(cfg.get("local_files_only", True))
    cli_path = ""
    model_path = ""

    if backend == "whisper-server":
        health_url = cfg.get("whisper_server_health_url", DEFAULTS["whisper_server_health_url"])
        startup_wait = int(cfg.get("whisper_server_startup_wait", 45))

        print("  backend: whisper-server")
        print(f"  server:  {cfg.get('whisper_server_url', DEFAULTS['whisper_server_url'])}")
        print(f"  health:  {health_url}")
        print(f"  waiting for server (up to {startup_wait}s)...")

        if not wait_for_server(health_url, startup_wait):
            print("  whisper-server is not ready")
            print("  start it with: systemctl --user start whisper-server.service")
            sys.exit(1)

        print("  server ready")
        run_warmup_if_enabled(cfg, backend, model, cli_path, model_path)
        notify("whisper-ptt", "ready (whisper-server)")

    elif backend == "whisper-cli":
        try:
            cli_path = find_whisper_cli(cfg)
            model_path = find_whisper_model(cfg)
        except FileNotFoundError as e:
            print(f"  {e}")
            print("  hint: set 'whisper_cli' and 'whisper_model_path' in config.json")
            sys.exit(1)

        w_threads = int(cfg.get("whisper_threads", 0) or 0)
        if w_threads <= 0:
            cores = os.cpu_count() or 4
            w_threads = max(4, cores - 2)
            cfg["whisper_threads"] = w_threads

        print("  backend: whisper-cli")
        print(f"  model:   {Path(model_path).name}")
        print(f"  cli:     {cli_path}")
        print(f"  threads: {w_threads}")
        print(
            f"  gpu:     {'on' if cfg.get('whisper_gpu', True) else 'off'}"
            f" (device {int(cfg.get('whisper_gpu_device', 0) or 0)})"
        )
        print("  engine ready")
        run_warmup_if_enabled(cfg, backend, model, cli_path, model_path)
        notify("whisper-ptt", f"ready (whisper-cli: {Path(model_path).name})")
    else:
        from faster_whisper import WhisperModel

        compute = cfg["compute_type"]
        requested_device = cfg.get("device", "auto")
        if requested_device == "auto" and compute == "int8":
            # CPU-safe default for int8; avoids auto-selecting CUDA on systems
            # where the driver is present but CUDA runtime libs are incomplete.
            runtime_device = "cpu"
        else:
            runtime_device = requested_device

        if runtime_device == "cpu" and cpu_threads <= 0:
            cores = os.cpu_count() or 4
            # leave 2 cores for desktop responsiveness
            cpu_threads = max(4, cores - 2)

        print("  backend: faster-whisper")
        print(f"  model:   {cfg['model']}")
        print(f"  device:  {runtime_device} (requested: {requested_device})")
        print(f"  compute: {compute}")
        if runtime_device == "cpu":
            print(f"  threads: {cpu_threads}")
        print("  loading model (downloads once if not already cached)...")

        try:
            model = WhisperModel(
                cfg["model"],
                device=runtime_device,
                compute_type=compute,
                cpu_threads=cpu_threads,
                local_files_only=local_files_only,
            )
        except Exception as e:
            if runtime_device != "cpu" and (is_cuda_error(e) or "float16" in str(e).lower()):
                print(f"  GPU unavailable, falling back to CPU int8")
                runtime_device = "cpu"
                compute = "int8"
                model = WhisperModel(
                    cfg["model"],
                    device="cpu",
                    compute_type="int8",
                    cpu_threads=cpu_threads,
                    local_files_only=local_files_only,
                )
            else:
                raise

        print(f"  model ready")
        run_warmup_if_enabled(cfg, backend, model, cli_path, model_path)
        notify("whisper-ptt", f"ready ({cfg['model']})")

    # find and exclusively grab the foot pedal
    dev = find_device(cfg)
    if not dev:
        name = cfg.get("device_name") or cfg.get("device_path") or "?"
        print(f"  pedal not found: {name}")
        print(f"  re-run: python ptt.py --setup")
        sys.exit(1)

    grabbed = False
    if cfg.get("exclusive_grab", True):
        try:
            dev.grab()
            grabbed = True
        except OSError as e:
            if e.errno == errno.EBUSY:
                print("  pedal is already grabbed by another process")
                print("  stop the other process, then retry")
                print("    systemctl --user stop whisper-ptt.service")
                print("    pkill -f whisper-ptt/ptt.py")
                print("  if needed, set \"exclusive_grab\": false in config.json")
                sys.exit(1)
            raise

    print(f"  pedal:   {dev.name} ({dev.path})")
    print(f"  grab:    {'exclusive' if grabbed else 'shared'}")

    left_code = getattr(ecodes, cfg["left_key"])
    right_code = getattr(ecodes, cfg["right_key"])
    print(f"  left:    {cfg['left_key']} -> quick")
    print(f"  right:   {cfg['right_key']} -> accurate")
    print(f"  listening...\n")

    recorder = Recorder(rate=cfg.get("sample_rate", 16000))
    active_key: int | None = None
    active_mode: str | None = None

    try:
        async for event in dev.async_read_loop():
            if event.type != ecodes.EV_KEY:
                continue

            code, value = event.code, event.value

            # --- key down: start recording ---
            if value == 1 and active_key is None:
                if code == left_code:
                    active_key, active_mode = code, "quick"
                elif code == right_code:
                    active_key, active_mode = code, "accurate"
                else:
                    continue
                recorder.start()
                print(f"  [rec] {active_mode}")

            # --- key up: stop, transcribe, type ---
            elif value == 0 and code == active_key:
                audio = recorder.stop()
                duration = len(audio) / cfg.get("sample_rate", 16000)
                print(f"  [stop] {duration:.1f}s")

                if len(audio) < 2400:  # < 0.15s — accidental tap
                    print("  (too short, skipped)")
                    active_key = active_mode = None
                    continue

                t0 = time.time()

                if backend == "whisper-server":
                    req_timeout = max(
                        5,
                        min(300, int(cfg.get("whisper_server_request_timeout", 120) or 120)),
                    )
                    try:
                        text = await asyncio.wait_for(
                            loop.run_in_executor(
                                None,
                                transcribe_whisper_server,
                                audio,
                                active_mode,
                                cfg,
                            ),
                            timeout=float(req_timeout + 2),
                        )
                    except asyncio.TimeoutError:
                        msg = f"whisper-server timeout after {req_timeout + 2}s"
                        print(f"  [err] {msg}")
                        notify("whisper-ptt", msg)
                        active_key = active_mode = None
                        continue
                    except RuntimeError as e:
                        print(f"  [err] {e}")
                        notify("whisper-ptt", str(e))
                        active_key = active_mode = None
                        continue
                elif backend == "whisper-cli":
                    try:
                        text = await loop.run_in_executor(
                            None,
                            transcribe_whisper_cli,
                            audio,
                            active_mode,
                            cfg,
                            cli_path,
                            model_path,
                        )
                    except RuntimeError as e:
                        print(f"  [err] {e}")
                        notify("whisper-ptt", str(e))
                        active_key = active_mode = None
                        continue
                else:
                    params = QUICK if active_mode == "quick" else ACCURATE
                    try:
                        text = await loop.run_in_executor(
                            None, transcribe, model, audio, params, cfg["language"]
                        )
                    except RuntimeError as e:
                        if runtime_device != "cpu" and is_cuda_error(e):
                            from faster_whisper import WhisperModel

                            print("  GPU runtime missing CUDA libs, switching to CPU int8")
                            runtime_device = "cpu"
                            compute = "int8"
                            model = WhisperModel(
                                cfg["model"],
                                device="cpu",
                                compute_type="int8",
                                cpu_threads=cpu_threads,
                                local_files_only=local_files_only,
                            )
                            text = await loop.run_in_executor(
                                None, transcribe, model, audio, params, cfg["language"]
                            )
                        else:
                            raise
                elapsed = time.time() - t0
                print(f"  [{elapsed:.1f}s] {text}")

                if text:
                    t_out = time.time()
                    out_timeout = max(2, min(60, int(cfg.get("output_timeout_s", 8) or 8)))
                    try:
                        ok, msg = await asyncio.wait_for(
                            loop.run_in_executor(
                                None,
                                output_text,
                                text,
                                cfg.get("output_mode", "type"),
                                cfg.get("typer", "auto"),
                                int(cfg.get("ydotool_key_delay_ms", 0) or 0),
                                cfg.get("paste_method", "auto"),
                                int(cfg.get("paste_min_chars", 24) or 0),
                            ),
                            timeout=float(out_timeout),
                        )
                    except asyncio.TimeoutError:
                        ok, msg = False, f"output timeout after {out_timeout}s"
                    except Exception as e:
                        ok, msg = False, f"output error: {e}"
                    out_elapsed_ms = (time.time() - t_out) * 1000.0
                    if ok:
                        print(f"  [out {out_elapsed_ms:.0f}ms] {msg}")

                        if active_mode == "accurate" and bool(cfg.get("submit_on_accurate", False)):
                            submit_delay_ms = max(0, min(2000, int(cfg.get("submit_delay_ms", 0) or 0)))
                            if submit_delay_ms:
                                await asyncio.sleep(submit_delay_ms / 1000.0)

                            submit_timeout = max(
                                1,
                                min(20, int(cfg.get("submit_timeout_s", 5) or 5)),
                            )
                            t_submit = time.time()
                            try:
                                s_ok, s_msg = await asyncio.wait_for(
                                    loop.run_in_executor(
                                        None,
                                        submit_enter,
                                        cfg.get("submit_typer", cfg.get("typer", "auto")),
                                    ),
                                    timeout=float(submit_timeout),
                                )
                            except asyncio.TimeoutError:
                                s_ok, s_msg = False, f"submit timeout after {submit_timeout}s"
                            except Exception as e:
                                s_ok, s_msg = False, f"submit error: {e}"

                            submit_elapsed_ms = (time.time() - t_submit) * 1000.0
                            if s_ok:
                                print(f"  [submit {submit_elapsed_ms:.0f}ms] {s_msg}")
                            else:
                                print(f"  [submit {submit_elapsed_ms:.0f}ms] {s_msg}")
                                notify("whisper-ptt", s_msg)
                    else:
                        print(f"  [out {out_elapsed_ms:.0f}ms] {msg}")
                        notify("whisper-ptt", msg)

                active_key = active_mode = None
    finally:
        try:
            if grabbed:
                dev.ungrab()
        except OSError:
            pass
        dev.close()


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    p = argparse.ArgumentParser(
        description="Dual foot-pedal push-to-talk with Whisper transcription",
    )
    p.add_argument("--list", action="store_true", help="list input devices")
    p.add_argument("--setup", action="store_true", help="interactive pedal detection")
    p.add_argument("--test-mic", action="store_true", help="record 3s and play back")
    p.add_argument(
        "--backend",
        choices=["faster-whisper", "whisper-cli", "whisper-server"],
        help="transcription backend",
    )
    p.add_argument("--device", help="evdev device path override")
    p.add_argument("--model", help="whisper model override")
    p.add_argument("--whisper-cli", help="path to whisper-cli binary")
    p.add_argument("--whisper-model", help="path to whisper.cpp ggml model")
    args = p.parse_args()

    if args.list:
        cmd_list()
        return

    if args.setup:
        cmd_setup()
        return

    if args.test_mic:
        cmd_test_mic()
        return

    cfg = load_cfg()
    if args.backend:
        cfg["backend"] = args.backend
    if args.device:
        cfg["device_path"] = args.device
        cfg["device_name"] = ""
    if args.model:
        cfg["model"] = args.model
    if args.whisper_cli:
        cfg["whisper_cli"] = args.whisper_cli
    if args.whisper_model:
        cfg["whisper_model_path"] = args.whisper_model

    if not cfg["device_name"] and not cfg["device_path"]:
        print("  no pedal configured")
        print("  run:  python ptt.py --setup")
        sys.exit(1)

    try:
        asyncio.run(run(cfg))
    except KeyboardInterrupt:
        print("\n  stopped")


if __name__ == "__main__":
    main()
