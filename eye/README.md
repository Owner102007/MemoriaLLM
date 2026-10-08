# Спутник взгляда (СНО2026)

Программа на Python, которая лежит рядом с приложением в ZIP ветвей
СНО2026 для Windows (`eye/` рядом с `memoria.exe`). Снимает веб-камеру,
находит ориентиры лица (MediaPipe), пишет признаки кадра
`features.bin` и полосу глаз `eyes.mp4`. Книг, журнала и экранов
приложения не знает. Схема — «Айтрекер — схема системы и план
внедрения» в описательной структуре; функции SNO-F-EYE-04, SNO-F-EYE-05.

## Для организатора

* `Проверка камеры.cmd` — самопроверка места и две минуты замера.
  Пока идёт замер, откройте в приложении книгу и листайте её.
  Итог — `bench.json` в папке `eye\bench\<дата-время>\`.
* `Проверка камеры (40 минут).cmd` — то же на сорок минут.

Ставить ничего не нужно: Python встроен.

## Для разработчика

```bash
python -m pip install --require-hashes --only-binary :all: --no-deps \
  -r requirements.lock -r requirements-dev.lock
python tool/fetch_model.py           # модель по замку (иначе её тесты пропускаются)
python -m pytest -q
python -m sno_eye bench --source synthetic --minutes 0.2 --no-window
```

* `python -m sno_eye serve` — обмен с приложением строками JSON через
  stdin/stdout (SNO-ALG-EYE-03);
* `python -m sno_eye --selftest` — пробный запуск собранной папки;
* `--source synthetic[:denied|busy|none|dark|noface|slow|twofaces]` —
  синтетика вместо камеры и модели.

Замки: `python_version.txt` (встраиваемый Python), `requirements.lock`
(колёса, `tool/make_lock.py`), `model_version.txt` (модель лица).
Подъём версий — отдельным шагом. Сборку папки делает CI
(`tool/build_windows.py`).
