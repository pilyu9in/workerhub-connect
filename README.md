<div align="center">

# WORKERHUB Connect

**Ваши приложения. Ваш ключ. Модели WORKERHUB.**

Подключение Claude и Codex к WORKERHUB одним файлом для Windows или macOS.

[Скачать для Windows](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd) · [Скачать для macOS](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub-macos.command) · [Релизы и SHA-256](https://github.com/pilyu9in/workerhub-connect/releases) · [English](README.en.md) · [WORKERHUB](https://workerhub.cc) · [Поддержка](https://t.me/workerhub_support)

Windows 10 / 11 · PowerShell 5.1 · macOS · Python 3.11+ · Русский / English · MIT

</div>

---

## Быстрый старт

1. Скачайте файл для своей системы. Приложение, которое хотите подключить, должно быть уже установлено.
   - **Windows:** откройте [workerhub.cmd](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd) двойным щелчком.
   - **macOS:** нужен Python 3.11 или новее. Скачайте [workerhub-macos.command](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub-macos.command), откройте Terminal и выполните:
     ```sh
     sh ~/Downloads/workerhub-macos.command
     ```
2. **Выберите язык и приложение** стрелками ↑ ↓, подтвердите Enter. Esc отменяет выбор.
3. **Вставьте API-ключ** из раздела «Обзор» в кабинете WORKERHUB и выберите модель. При вводе ключ скрыт.
4. **Полностью перезапустите приложение или терминал**, включая фоновые процессы.

Чтобы подключить другое приложение или сменить модель, запустите файл ещё раз. Codex и Codex CLI используют общие настройки.

```text
WORKERHUB

Что подключить?
  Claude Desktop
  Claude Code CLI
> Codex
  Codex CLI
```

Установщики только настраивают подключение: они не устанавливают и не обновляют Claude или Codex. Для Windows используется встроенный PowerShell 5.1; для macOS нужен Python 3.11+ и Terminal. Node.js и права администратора не требуются.

## Что подключается

| Приложение | Что настраивает скрипт |
| --- | --- |
| **Claude Desktop** | Профиль WORKERHUB в режиме стороннего шлюза, API-ключ и список доступных моделей Claude. Настройки профиля создаются для Windows или macOS; выбранная модель становится первой в списке. |
| **Claude Code CLI** | Адрес шлюза, ключ, модель по умолчанию и псевдонимы семейств Claude в пользовательском окружении Windows или `~/.claude/settings.json` на macOS. |
| **Codex** | Провайдер WORKERHUB, модель по умолчанию и локальный каталог совместимых моделей в общих настройках Codex на Windows или macOS. |
| **Codex CLI** | То же подключение, что и у приложения Codex. Существующий официальный вход сохраняется. |

### Модели и стоимость

Список моделей загружается из актуального каталога WORKERHUB при каждом запуске. Для Codex он сверяется с официальными метаданными клиента. Показываются только подходящие текстовые модели; модели изображений и аудио не добавляются.

Модели **не скачиваются на компьютер**. Запросы отправляются через WORKERHUB и оплачиваются с баланса аккаунта по действующим тарифам. Скрипт не отправляет платных запросов и не проверяет ключ через генерацию: его работоспособность проверится при первом запросе приложения.

У Claude Code CLI настраиваются модель по умолчанию и доступные семейства; скрипт не добавляет ему отдельный полный каталог выбора. Для обновления списка моделей в Desktop/Codex запустите скрипт заново.

## Как это работает

| Клиент | Адрес подключения |
| --- | --- |
| Claude Desktop / Claude Code CLI | `https://workerhub.cc/worker-api` |
| Codex / Codex CLI | `https://workerhub.cc/worker-api/v1` |

Для Claude используется корневой адрес Anthropic-совместимого шлюза: клиент сам добавляет `/v1/messages`. Codex использует Responses API. Выбирать адрес вручную не нужно.

<details>
<summary><strong>Какие настройки меняются</strong></summary>

**Claude Code CLI**

На Windows сохраняются пользовательские переменные `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, псевдонимы `ANTHROPIC_DEFAULT_*_MODEL` и настройки вспомогательной модели. На macOS те же параметры записываются в `~/.claude/settings.json` внутри `env`. В обоих случаях `ANTHROPIC_API_KEY` очищается, а режимы Bedrock/Vertex/Foundry отключаются, чтобы не конфликтовать с выбранным шлюзом.

**Claude Desktop**

В Windows-папке `%LOCALAPPDATA%\Claude` включается `deploymentMode = "3p"` и создаётся профиль в `Claude-3p\configLibrary`. На macOS те же файлы располагаются в `~/Library/Application Support/Claude` и `~/Library/Application Support/Claude-3p`. Отдельный профиль WORKERHUB активируется, остальные профили сохраняются.

**Codex / Codex CLI**

В `config.toml` обновляются выбранная модель, провайдер `model_providers.workerhub` и путь к `workerhub-models.json`. Windows использует `%USERPROFILE%\.codex`, macOS — `~/.codex`; `CODEX_HOME` переопределяет папку на обеих системах. На Windows ключ хранится в `WORKERHUB_API_KEY`; на macOS — в `~/.workerhub/api-key` с правами только для владельца, а отдельная команда читает его при запросе Codex. `auth.json` не изменяется.

Ключ хранится локально без дополнительного шифрования: в переменной окружения или профиле Claude Desktop на Windows, в пользовательских JSON-настройках Claude на macOS, а для Codex на macOS — в файле `~/.workerhub/api-key` с правами `600`. Не публикуйте эти настройки и резервные копии с ключом.

</details>

<details>
<summary><strong>Резервные копии и возврат настроек</strong></summary>

Перед изменением существующего файла создаётся точная копия рядом с ним: `имя-файла.workerhub-ДАТА-ID.bak`. При ошибке записи скрипт пытается откатить изменения текущего запуска. Одновременное изменение файла другой программой прерывает настройку.

Для ручного возврата закройте приложение и восстановите нужную соседнюю `.bak`-копию. Настройки новых файлов, у которых не было предыдущей версии, нужно удалить вручную, если они больше не нужны.

На Windows переменные окружения не имеют файловых `.bak`-копий и восстанавливаются отдельно. На macOS значения Claude Code лежат в `~/.claude/settings.json`; ключ Codex — в `~/.workerhub/api-key`. Восстановите соседние `.bak`-файлы для изменённых настроек, а созданные впервые файлы удалите, если они больше не нужны. Для Claude Desktop можно выбрать прежний профиль. `CODEX_HOME` учитывается и при создании каталогов.

</details>

## Если что-то не получилось

| Ситуация | Что сделать |
| --- | --- |
| Приложение использует старое подключение | Полностью закройте его, включая фоновые процессы, и откройте снова. Для CLI откройте новый терминал; при запуске из IDE перезапустите и её. Локальные переопределения клиента могут иметь приоритет над пользовательским окружением. |
| Ошибка загрузки каталога | Проверьте доступ к WORKERHUB и GitHub, затем повторите запуск. До загрузки каталога настройки не записываются. |
| Ошибка ключа или баланса в приложении | Проверьте активность ключа и баланс в кабинете. Вставляйте сам ключ, без `Bearer` и пробелов. |
| В Codex Desktop не видны модели | Перезапустите приложение. В некоторых версиях список зависит от официального входа в Codex; существующий вход скрипт сохраняет. При необходимости проверьте подключение через Codex CLI. |
| Скрипт отказался менять `config.toml` | Обычные секции, включая пути и плагины в кавычках, поддерживаются. Многострочные строки и некоторые inline/dotted определения провайдеров намеренно отклоняются. Используйте отдельный `CODEX_HOME` или настройте провайдера вручную. |
| На macOS пишет, что нужен Python | Установите Python 3.11 или новее, затем снова запустите `.command` из Terminal. |
| На macOS не работают стрелки | Запустите файл в Terminal, а не в редакторе или без интерактивного терминала. |
| Файл открылся как текст | Сохраните именно файл установщика, а не HTML-страницу или `.txt`; на Mac запускайте его из Terminal. |

## Исходный код и проверка скачивания

Оба файла релиза берутся из исходников под тегом версии. В том же релизе лежит `SHA256SUMS.txt` с контрольными суммами обоих файлов. Если файл сохранился в «Загрузки», сравните результат команды со строкой для вашей системы в `SHA256SUMS.txt`.

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\workerhub.cmd" -Algorithm SHA256
```

```sh
shasum -a 256 ~/Downloads/workerhub-macos.command
```

## Для разработчиков

Код установщика Windows находится в [workerhub.cmd](workerhub.cmd); файл macOS — это [workerhub-macos.command](workerhub-macos.command) со встроенным Python-кодом. Для Windows используется встроенный PowerShell, системная политика выполнения не меняется.

Windows-скрипт хранится в UTF-8 без BOM с окончаниями строк CRLF. GitHub Actions запускает Windows-проверки PowerShell и отдельные проверки установщика macOS, в том числе синтаксиса shell и тестов настройки. Тесты используют временные каталоги и фиктивные ключи; запросы генерации не отправляются.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

```sh
sh -n workerhub-macos.command
python3 -m unittest discover -s tests -p 'test_macos_command.py' -v
```

Нашли ошибку? [Создайте issue](https://github.com/pilyu9in/workerhub-connect/issues), указав систему, приложение и текст ошибки. Удалите API-ключи из логов и конфигурации перед отправкой.

## Лицензия

[MIT](LICENSE). Claude и Codex — продукты их соответствующих владельцев. WORKERHUB Connect — отдельный инструмент настройки стороннего подключения.
