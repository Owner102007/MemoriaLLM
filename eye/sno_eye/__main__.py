"""`python -I -m sno_eye …` — вход спутника.

* `serve` — обмен с приложением строками JSON (SNO-ALG-EYE-03);
* `bench` — стенд «Проверка камеры» (ворота Г1);
* `check [архив или папка …]` — «Проверка записи»: годна ли запись
  сессии (SNO-F-RES-01, шаг 33); без имён — записи на этом ПК;
* `--selftest` — пробный запуск собранной папки (CI и организатор).

`--source synthetic[:вариант]` подменяет камеру и распознавание
синтетикой — для тестов.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys

os.environ.setdefault("MPLBACKEND", "Agg")


def _utf8_stdio() -> None:
    # Под `-I` на Windows потоки — в кодировке ANSI, с буферизацией и
    # `\r\n`: ломались бы кириллические имена камер и пути.
    for stream in (sys.stdin, sys.stdout):
        try:
            stream.reconfigure(encoding="utf-8", newline="\n", line_buffering=True)
        except (AttributeError, ValueError):
            pass
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def main(argv: list[str] | None = None) -> int:
    _utf8_stdio()
    ap = argparse.ArgumentParser(prog="sno_eye")
    ap.add_argument("command", nargs="?", choices=("serve", "bench", "check"))
    ap.add_argument("paths", nargs="*",
                    help="check: архивы записей или папки с ними")
    ap.add_argument("--json", action="store_true",
                    help="check: итог строкой JSON")
    ap.add_argument("--csv", help="check: куда положить сводную таблицу")
    ap.add_argument("--no-csv", action="store_true",
                    help="check: без сводной таблицы")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--linger", type=float, default=0.0)
    ap.add_argument("--source", default="camera")
    ap.add_argument("--minutes", type=float, default=2.0)
    ap.add_argument("--camera", type=int)
    ap.add_argument("--no-window", action="store_true")
    ap.add_argument("--out")
    ap.add_argument("--log")
    ap.add_argument("--selfcheck-seconds", type=float)
    ap.add_argument("--clock-offset-us", type=int, default=0,
                    help="сдвиг часов спутника — только для тестов")
    args = ap.parse_args(argv)

    handlers: list[logging.Handler] = [logging.StreamHandler(sys.stderr)]
    if args.log:
        handlers.append(logging.FileHandler(args.log, encoding="utf-8"))
    logging.basicConfig(level=logging.INFO, handlers=handlers,
                        format="%(asctime)s %(name)s %(message)s")

    if args.clock_offset_us:
        from . import clock
        clock.set_offset_us(args.clock_offset_us)

    if args.selftest:
        from .selftest import run
        return run(linger=args.linger, source=args.source)

    if args.command is None:
        ap.print_help()
        return 2

    if args.paths and args.command != "check":
        ap.error("имена файлов принимает только check")

    # «Проверка записи» камеры не трогает и может идти рядом с
    # приложением и спутником — без замка единственного экземпляра.
    if args.command == "check":
        from .record_check import main as check
        return check(args.paths, as_json=args.json, csv_path=args.csv,
                     write_table=not args.no_csv)

    from .runtime import Runtime, SingleInstance

    lock = SingleInstance()
    if not lock.acquire():
        msg = {"v": 1, "error": "already_running", "text": "Спутник уже запущен"}
        if args.command == "serve":
            print(json.dumps(msg, ensure_ascii=False), flush=True)
        else:
            print("Спутник уже запущен: закройте приложение или другое окно "
                  "проверки камеры.", flush=True)
        return 3
    try:
        if args.command == "serve":
            from .protocol import serve
            return serve(Runtime(args.source))
        from pathlib import Path
        from .bench import run
        return run(minutes=args.minutes, camera=args.camera,
                   window=not args.no_window, source=args.source,
                   out_dir=Path(args.out) if args.out else None,
                   interactive=sys.stdin.isatty(),
                   selfcheck_seconds=args.selfcheck_seconds)
    finally:
        lock.release()


if __name__ == "__main__":
    sys.exit(main())
