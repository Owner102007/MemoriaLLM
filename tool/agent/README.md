# Автопроверка: как Claude запускает и проверяет приложение

Шаг S56.1, разведка RS-05. Всё здесь — для отладочной сборки; в выпуск не
попадает ничего.

## Своя папка данных (F-REL-10)
Любой автопрогон собирается с `--dart-define=MEMORIA_DATA_DIR=<новая папка>`.
Тогда база, обложки и копии книг ложатся туда, а не в
`%APPDATA%\HohloBaron\Memoria LLM HB` — полка владельца не трогается.
Сценарии и точка входа агента без этой папки не стартуют.

## Сценарии (F-REL-09)
`integration_test/` — запуск настоящего приложения (`startApp` из
`lib/main.dart`) с подменой только системного выбора файла.

```bash
powershell -File tool/agent/scenarios.ps1                        # на ПК
powershell -File tool/agent/scenarios.ps1 -Device emulator-5554  # в эмуляторе
```
Скрипт создаёт новую папку в `%TEMP%\memoria-auto\` и передаёт её сборке.

## Живое приложение для агента (F-REL-11)
Marionette MCP (LeanCode, Apache-2.0): Claude видит кнопки, нажимает, вводит,
листает, снимает экран.

```bash
flutter run -d windows -t tool/agent/main_agent.dart --dart-define=MEMORIA_DATA_DIR=%TEMP%\memoria-auto\live
```
В выводе `flutter run` — адрес VM service; его получает инструмент `connect`
сервера `marionette`. Сам сервер, Flutter, Android SDK и эмулятор ставит
инструмент экосистемы `TOOLS/TOOL Окружение Для Тестов` (`ПОДКЛЮЧИТЬ.cmd`,
ECO-D-030); там же `agent/emulator.ps1` и `agent/marionette.mjs`.

## Чего здесь нет
Настоящий диалог выбора файла Windows и системные окна Android Flutter не
видит. Окна Android — Patrol (F-REL-12), диалог Windows — ручная проверка.
