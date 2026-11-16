#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GamePath,
    [switch]$DryRun,
    [switch]$Elevated,
    [switch]$Force,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath = $MyInvocation.MyCommand.Path
$StateRoot = Join-Path $env:LOCALAPPDATA 'IsaacRebirthNoDLCKit'
$StatePath = Join-Path $StateRoot 'install_state.json'
$HudInstallDir = Join-Path $StateRoot 'HUD'
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = if ($DesktopDir) { Join-Path $DesktopDir 'Isaac Rebirth HUD.lnk' } else { $null }

function Write-Title {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  Удаление Isaac Rebirth No-DLC Kit' -ForegroundColor Cyan
    Write-Host '  EID Rebirth + MissingHUD2' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Read-Choice {
    param([string]$Prompt, [string[]]$Options, [int]$Default = 1)
    while ($true) {
        Write-Host ''
        Write-Host $Prompt -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i])
        }
        $answer = Read-Host ("Выбор (Enter = {0})" -f $Default)
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) { return $n }
        Write-Host 'Неверный ввод. Введите номер пункта.' -ForegroundColor Yellow
    }
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WriteAccess {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    try {
        $tmp = Join-Path $Path ('.kit_write_test_' + [guid]::NewGuid().ToString('N') + '.tmp')
        [System.IO.File]::WriteAllText($tmp, 'test')
        Remove-Item -LiteralPath $tmp -Force
        return $true
    } catch { return $false }
}

function Invoke-Elevated {
    param([string]$Path)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath), '-Elevated')
    if ($Path) { $argList += @('-GamePath', ('"{0}"' -f $Path)) }
    if ($Force) { $argList += '-Force' }
    if ($Pause) { $argList += '-Pause' }
    Write-Host 'Требуются права администратора. Запрашиваю UAC...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
        exit $proc.ExitCode
    } catch {
        Write-Host 'Не удалось получить права администратора. Удаление отменено.' -ForegroundColor Red
        exit 1
    }
}

function Resolve-GamePath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim()
    if ($p.StartsWith('"') -and $p.EndsWith('"') -and $p.Length -ge 2) {
        $p = $p.Substring(1, $p.Length - 2)
    }
    try { $p = [System.IO.Path]::GetFullPath($p) } catch { return $null }
    if ((Test-Path -LiteralPath (Join-Path $p 'isaac-ng.exe') -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $p 'resources') -PathType Container)) {
        return $p.TrimEnd('\')
    }
    return $null
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Remove-EmptyDirectories {
    param([string]$ResourcesRoot)
    if (-not (Test-Path -LiteralPath $ResourcesRoot -PathType Container)) { return }
    $dirs = Get-ChildItem -LiteralPath $ResourcesRoot -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending
    foreach ($dir in $dirs) {
        try {
            $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction Stop)
            if ($children.Count -eq 0) {
                Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction Stop
            }
        } catch { }
    }
}

function Remove-Hud {
    param([string]$Target, [string]$Shortcut)
    if ($Shortcut -and (Test-Path -LiteralPath $Shortcut)) {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $lnk = $shell.CreateShortcut($Shortcut)
            if ($lnk.TargetPath -eq (Join-Path $Target 'START_HUD.bat')) {
                Remove-Item -LiteralPath $Shortcut -Force
            }
        } catch {
            Remove-Item -LiteralPath $Shortcut -Force -ErrorAction SilentlyContinue
        }
    }
    if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
    }
}

function Wait-GameClosed {
    if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Warning 'Игра сейчас запущена. Перед удалением её нужно закрыть.'
            return
        }
        Write-Host 'Игра сейчас запущена.' -ForegroundColor Yellow
        if ($Force) { throw 'Закройте The Binding of Isaac: Rebirth и повторите удаление.' }
        while ($true) {
            Read-Host 'Закройте игру и нажмите Enter (Ctrl+C - отмена)'
            if (-not (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)) { break }
            Write-Host 'Игра всё ещё запущена.' -ForegroundColor Yellow
        }
    }
}

function Wait-HudClosed {
    if (Get-Process -Name 'MissingHUD2' -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Warning 'MissingHUD2 сейчас запущен. Перед удалением его нужно закрыть.'
            return
        }
        Write-Host 'MissingHUD2 сейчас запущен.' -ForegroundColor Yellow
        if ($Force) { throw 'Закройте MissingHUD2 и повторите удаление.' }
        while ($true) {
            Read-Host 'Закройте MissingHUD2 и нажмите Enter (Ctrl+C - отмена)'
            if (-not (Get-Process -Name 'MissingHUD2' -ErrorAction SilentlyContinue)) { break }
            Write-Host 'MissingHUD2 всё ещё запущен.' -ForegroundColor Yellow
        }
    }
}

$exitCode = 0
try {
    Write-Title
    if ($DryRun) {
        Write-Host 'РЕЖИМ DRYRUN: файлы не изменяются, только проверка.' -ForegroundColor Yellow
        Write-Host ''
    }

    if (-not (Test-Path -LiteralPath $StatePath)) {
        Write-Host 'Не найден файл состояния установки:' -ForegroundColor Yellow
        Write-Host ("  {0}" -f $StatePath) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'Похоже, набор не установлен или состояние было удалено.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host 'Удалить вручную:' -ForegroundColor White
        Write-Host '  1. Закройте игру и MissingHUD2.'
        Write-Host '  2. В папке игры resources удалите gfx, animations.b и pocketitems.xml,'
        Write-Host '     если вы точно устанавливали их этим набором и не используете другие моды.'
        Write-Host ("  3. Удалите папку {0}" -f $StateRoot)
        Write-Host '  4. Удалите ярлык Isaac Rebirth HUD с рабочего стола.'
        Write-Host ''
        if (Test-Path -LiteralPath $HudInstallDir) {
            $choice = Read-Choice 'Удалить хотя бы папку HUD и ярлык?' @('Да', 'Нет') 1
            if ($choice -eq 1) {
                if (-not $DryRun) {
                    Wait-HudClosed
                    try { Remove-Hud -Target $HudInstallDir -Shortcut $ShortcutPath } catch { Write-Warning $_.Exception.Message }
                }
                Write-Host 'HUD и ярлык удалены.' -ForegroundColor Green
            }
        }
        exit 1
    }

    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    Write-Host ("Установлено: {0}" -f $state.installedAt)
    Write-Host ("Папка игры: {0}" -f $state.gamePath)
    Write-Host ("Язык: {0}" -f $(if ($state.language -eq 'ru') { 'русский' } else { 'English' }))
    Write-Host ("Файлов в состоянии: {0}" -f @($state.files).Count)
    Write-Host ''

    if ($GamePath) {
        $game = Resolve-GamePath $GamePath
        if (-not $game) { throw "Указанный путь не похож на папку игры: $GamePath" }
    } else {
        $game = Resolve-GamePath $state.gamePath
    }

    $hudOnly = $false
    if (-not $game) {
        Write-Warning 'Папка игры не найдена (игра могла быть перемещена или удалена).'
        if ($DryRun) {
            Write-Host 'DRYRUN: файлы EID не будут обработаны, HUD и ярлык будут удалены.' -ForegroundColor Yellow
        } else {
            $choice = Read-Choice 'Что делать?' @('Удалить только HUD и ярлык', 'Выйти') 1
            if ($choice -eq 2) { exit 1 }
            $hudOnly = $true
        }
    } else {
        Write-Host ("Игра: {0}" -f $game) -ForegroundColor Green
        if (-not $DryRun -and -not (Test-WriteAccess $game) -and -not (Test-IsAdmin)) {
            Invoke-Elevated -Path $game
        }
        if (-not $DryRun -and -not (Test-WriteAccess $game)) {
            throw 'Нет прав на запись в папку игры. Запустите UNINSTALL.bat от имени администратора.'
        }
    }

    Wait-GameClosed
    Wait-HudClosed

    $deleteCount = 0
    $restoreCount = 0
    $keepCount = 0
    $missingCount = 0
    $backupMissing = New-Object System.Collections.Generic.List[string]
    $kept = New-Object System.Collections.Generic.List[string]
    $records = @($state.files)
    $backupDir = $state.backupDir

    foreach ($rec in $records) {
        $action = [string]$rec.action
        if ($action -eq 'preexisting') { continue }
        if (-not $game) { continue }

        $target = Join-Path $game ([string]$rec.path)
        $exists = Test-Path -LiteralPath $target -PathType Leaf

        if ($action -eq 'created') {
            if (-not $exists) { $missingCount++; continue }
            $hash = Get-FileSha256 $target
            if ($hash -eq [string]$rec.sha256) { $deleteCount++ }
            else { $keepCount++; $kept.Add([string]$rec.path) }
        } elseif ($action -eq 'replaced') {
            $backupPath = $null
            if ($backupDir -and $rec.backupRel) {
                $backupPath = Join-Path $backupDir ([string]$rec.backupRel)
            }
            if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                $backupMissing.Add([string]$rec.path)
                $keepCount++
                continue
            }
            if (-not $exists) { $restoreCount++; continue }
            $hash = Get-FileSha256 $target
            if ($hash -eq [string]$rec.sha256) { $restoreCount++ }
            else { $keepCount++; $kept.Add([string]$rec.path) }
        }
    }

    Write-Host ''
    Write-Host 'План удаления:' -ForegroundColor White
    if (-not $hudOnly) {
        Write-Host ("  Будет удалено файлов EID: {0}" -f $deleteCount)
        Write-Host ("  Будет восстановлено из резервных копий: {0}" -f $restoreCount)
        Write-Host ("  Уже отсутствует: {0}" -f $missingCount)
    } else {
        Write-Host '  Файлы EID не трогаем (папка игры не найдена).'
    }
    Write-Host ("  Будет оставлено изменённых/чужих файлов: {0}" -f $keepCount)
    if ($backupMissing.Count -gt 0) {
        Write-Host ("  Не хватает резервных копий: {0}" -f $backupMissing.Count) -ForegroundColor Yellow
    }
    Write-Host ("  HUD: {0}" -f $HudInstallDir)
    if ($state.hud) {
        if ($state.hud.shortcut) {
            Write-Host ("  Ярлык: {0}" -f $state.hud.shortcut)
        } else {
            Write-Host '  Ярлык: не создавался'
        }
    } elseif ($ShortcutPath) {
        Write-Host ("  Ярлык: {0} (если существует)" -f $ShortcutPath)
    }
    Write-Host ''

    if ($DryRun) {
        if ($kept.Count -gt 0) {
            Write-Host 'Файлы, которые останутся (изменены после установки):' -ForegroundColor Yellow
            $kept | Select-Object -First 20 | ForEach-Object { Write-Host ("  {0}" -f $_) }
            if ($kept.Count -gt 20) { Write-Host ("  ... и ещё {0}" -f ($kept.Count - 20)) }
        }
        Write-Host ''
        Write-Host 'DRYRUN: изменения не вносятся.' -ForegroundColor Yellow
        Write-Host 'Проверка завершена.' -ForegroundColor Green
        exit 0
    }

    if (-not $Force) {
        $choice = Read-Choice 'Удалить набор и восстановить файлы?' @('Удалить', 'Отмена') 1
        if ($choice -eq 2) {
            Write-Host 'Отменено.' -ForegroundColor Yellow
            exit 0
        }
    }

    if (-not $hudOnly) {
        $i = 0
        foreach ($rec in $records) {
            $i++
            $action = [string]$rec.action
            if ($action -eq 'preexisting') { continue }
            $target = Join-Path $game ([string]$rec.path)

            if ($action -eq 'created') {
                if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
                $hash = Get-FileSha256 $target
                if ($hash -eq [string]$rec.sha256) {
                    Remove-Item -LiteralPath $target -Force
                }
            } elseif ($action -eq 'replaced') {
                $backupPath = $null
                if ($backupDir -and $rec.backupRel) {
                    $backupPath = Join-Path $backupDir ([string]$rec.backupRel)
                }
                if (-not $backupPath -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { continue }
                $exists = Test-Path -LiteralPath $target -PathType Leaf
                if ($exists) {
                    $hash = Get-FileSha256 $target
                    if ($hash -ne [string]$rec.sha256) { continue }
                }
                $parent = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $parent)) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }
                Copy-Item -LiteralPath $backupPath -Destination $target -Force
            }

            if ($i % 100 -eq 0) {
                Write-Progress -Activity 'Удаление EID' -Status ("{0} / {1}" -f $i, $records.Count) -PercentComplete (($i / [double]$records.Count) * 100)
            }
        }
        Write-Progress -Activity 'Удаление EID' -Completed
        Remove-EmptyDirectories (Join-Path $game 'resources')
    }

    $hudDirToRemove = if ($state.hud -and $state.hud.dir) { [string]$state.hud.dir } else { $HudInstallDir }
    $shortcutToRemove = if ($state.hud -and $state.hud.shortcut) { [string]$state.hud.shortcut } else { $null }
    try {
        Remove-Hud -Target $hudDirToRemove -Shortcut $shortcutToRemove
        Write-Host 'HUD и ярлык удалены.' -ForegroundColor Green
    } catch {
        Write-Warning ("Не удалось полностью удалить HUD: {0}" -f $_.Exception.Message)
    }

    if ($kept.Count -gt 0) {
        $keptLog = Join-Path $StateRoot ('uninstall_kept_files_{0}.txt' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
        try {
            New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
            $kept | Set-Content -LiteralPath $keptLog -Encoding UTF8
            Write-Host ("Список оставленных файлов: {0}" -f $keptLog) -ForegroundColor Yellow
        } catch { }
    }

    $archive = Join-Path $StateRoot ('uninstall_log_{0}.json' -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Move-Item -LiteralPath $StatePath -Destination $archive -Force

    Write-Host ''
    Write-Host 'Удаление завершено.' -ForegroundColor Green
    if (-not $hudOnly) {
        Write-Host 'Файлы игры восстановлены из резервных копий (если они были).'
    }
    if ($backupDir) {
        Write-Host ("Резервные копии сохранены: {0}" -f $backupDir) -ForegroundColor DarkGray
        Write-Host 'Их можно удалить вручную, когда убедитесь, что игра работает нормально.'
    }
    Write-Host ("Журнал удаления: {0}" -f $archive) -ForegroundColor DarkGray
    if ($kept.Count -gt 0) {
        Write-Host ("Оставлено изменённых файлов: {0}. Они перечислены в журнале." -f $kept.Count) -ForegroundColor Yellow
    }
} catch {
    Write-Host ''
    Write-Host ("ОШИБКА: {0}" -f $_.Exception.Message) -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($Pause -and -not $DryRun) {
        Write-Host ''
        [void](Read-Host 'Нажмите Enter, чтобы закрыть окно')
    }
}
exit $exitCode
