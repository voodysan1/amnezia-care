![Amnezia Care — диагностика и восстановление](assets/amnezia-care.svg)

# Amnezia Care

Диагностика причин, по которым ChatGPT и Claude работают медленно через VPN. Инструмент проверяет Windows, DNS, маршруты, HTTPS, IPv4/IPv6 и конфигурацию hosts.

> **Важно:** полный запуск нового установщика на Windows ещё не проверен. Сначала используйте режим диагностики.

## Быстрый старт

1. [Скачайте ZIP](https://github.com/voodysan1/amnezia-care/archive/refs/heads/main.zip).
2. Распакуйте архив.
3. Откройте PowerShell в папке.
4. Запустите только диагностику:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Care.ps1 -DiagnoseOnly
```

Диагностика ничего не меняет в системе. Отчёт сохраняется локально.

## Установщик

[Скачать Install-AmneziaCare.ps1](https://raw.githubusercontent.com/voodysan1/amnezia-care/main/Install-AmneziaCare.ps1)

Установщик сохраняет копию файлов и размещает инструмент в:

```text
%LOCALAPPDATA%\AmneziaCare\tool
```

Запуск:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-AmneziaCare.ps1
```

## Восстановление

Для возврата сохранённого файла hosts:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Care.ps1 -Restore "$env:LOCALAPPDATA\AmneziaCare\backups\hosts-ID.backup"
```

## Состав

- `Care.ps1` — диагностика Windows и проверка hosts.
- `Install-AmneziaCare.ps1` — установщик.
- `Start.cmd` — запуск из папки.
- `server-check.sh` — проверки Ubuntu / Docker.
- `CASE-STUDY.md` — описание сценариев.
- `PROMPT.md` — технический промпт.

Инструмент не публикует личные адреса серверов, почту, пароли, ключи или диагностические отчёты. Не запускайте режим исправления без понимания предлагаемых изменений.
