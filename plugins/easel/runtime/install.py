"""Easel's opt-in dependency installer. It never runs during MCPB extraction."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import venv
from pathlib import Path


def run(*args: str, env: dict[str, str] | None = None) -> None:
    print("运行：" + " ".join(args), flush=True)
    subprocess.run(args, check=True, env=env)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--job-id", required=True)
    parser.add_argument("--ffmpeg-directory", type=Path)
    parser.add_argument("--install-ffmpeg-with-brew", action="store_true")
    args = parser.parse_args()
    workspace = args.workspace.expanduser().resolve()
    runtime = workspace / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    for name in ("profiles", "state", "outputs", "cache"):
        (workspace / name).mkdir(parents=True, exist_ok=True)
    venv_root = runtime / "venv"
    python = venv_root / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
    browsers = runtime / "browsers"
    if python.exists() and subprocess.run([str(python), "-c", "import encodings"], capture_output=True).returncode != 0:
        shutil.rmtree(venv_root)
    if not python.exists():
        print("创建 Easel 专用 Python 环境", flush=True)
        # Standalone macOS Python builds (including uv-managed interpreters)
        # cannot run ensurepip after their executable is copied away from its
        # stdlib; venv's normal symlink mode keeps the interpreter valid.
        venv.EnvBuilder(with_pip=True, symlinks=os.name != "nt").create(venv_root)
    requirements = Path(__file__).with_name("requirements.txt")
    run(str(python), "-m", "pip", "install", "--disable-pip-version-check", "-r", str(requirements))
    environment = os.environ.copy()
    environment["PLAYWRIGHT_BROWSERS_PATH"] = str(browsers)
    run(str(python), "-m", "playwright", "install", "chromium", env=environment)
    ffmpeg_dir = args.ffmpeg_directory.expanduser().resolve() if args.ffmpeg_directory else None
    if ffmpeg_dir is not None:
        if not (ffmpeg_dir / "ffmpeg").is_file() or not (ffmpeg_dir / "ffprobe").is_file():
            raise RuntimeError("选择的目录必须同时包含 ffmpeg 和 ffprobe")
    if not ffmpeg_dir and args.install_ffmpeg_with_brew:
        brew = shutil.which("brew")
        if not brew:
            raise RuntimeError("未找到 Homebrew；请先安装 Homebrew，或手动指定 FFmpeg 目录")
        run(brew, "install", "ffmpeg")
    ffmpeg = str(ffmpeg_dir / "ffmpeg") if ffmpeg_dir else shutil.which("ffmpeg")
    ffprobe = str(ffmpeg_dir / "ffprobe") if ffmpeg_dir else shutil.which("ffprobe")
    if not ffmpeg or not ffprobe:
        raise RuntimeError("缺少 ffmpeg/ffprobe；请在向导中选择 Homebrew 安装或指定已有目录")
    run(ffmpeg, "-version")
    run(ffprobe, "-version")
    run(str(python), "-c", "import PIL, playwright")
    receipt = {"ready": True, "python": str(python), "browsers": str(browsers), "ffmpeg": ffmpeg, "ffprobe": ffprobe}
    temporary = runtime / "install-status.tmp"
    temporary.write_text(json.dumps(receipt, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(runtime / "install-status.json")
    (runtime / "setup-job.json").write_text(json.dumps({"jobId": args.job_id, "stage": "complete", "exitCode": 0}), encoding="utf-8")
    print("Easel 依赖安装完成", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        try:
            args = sys.argv
            job_id = args[args.index("--job-id") + 1]
            workspace = Path(args[args.index("--workspace") + 1]).expanduser().resolve()
            (workspace / "runtime" / "setup-job.json").write_text(json.dumps({"jobId": job_id, "stage": "failed", "exitCode": 1, "error": str(error)}, ensure_ascii=False), encoding="utf-8")
        except (ValueError, IndexError, OSError):
            pass
        print(f"Easel 安装失败：{error}", file=sys.stderr, flush=True)
        sys.exit(1)
