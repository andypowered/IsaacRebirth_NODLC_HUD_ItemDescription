#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GamePath,
    [ValidateSet('ru', 'en')]
    [string]$Lang,
    [switch]$DryRun,
    [switch]$Elevated,
    [switch]$NoShortcut,
    [switch]$Shortcut,
    [switch]$Force,
    [switch]$Pause
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)

$KitRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath = $MyInvocation.MyCommand.Path
$KitVersion = '1.0'
$StateRoot = Join-Path $env:LOCALAPPDATA 'IsaacRebirthNoDLCKit'
$StatePath = Join-Path $StateRoot 'install_state.json'
$BackupRootBase = Join-Path $StateRoot 'backup'
$HudInstallDir = Join-Path $StateRoot 'HUD'
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = if ($DesktopDir) { Join-Path $DesktopDir 'Isaac Rebirth HUD.lnk' } else { $null }
$EidPayload = Join-Path $KitRoot 'payload\EID'
$RuPayload = Join-Path $KitRoot 'payload\RU'
$HudPayload = Join-Path $KitRoot 'HUD'

function Write-Title {
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host '  The Binding of Isaac: Rebirth (без DLC)' -ForegroundColor Cyan
    Write-Host '  EID Rebirth + MissingHUD2 v1.4.0' -ForegroundColor Cyan
    Write-Host '============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Write-Step {
    param([int]$Number, [int]$Total, [string]$Text)
    Write-Host ''
    Write-Host ("[{0}/{1}] {2}" -f $Number, $Total, $Text) -ForegroundColor Cyan
}

function Read-Choice {
    param(
        [string]$Prompt,
        [string[]]$Options,
        [int]$Default = 1
    )
    while ($true) {
        Write-Host ''
        Write-Host $Prompt -ForegroundColor White
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-Host ("  [{0}] {1}" -f ($i + 1), $Options[$i])
        }
        $answer = Read-Host ("Выбор (Enter = {0})" -f $Default)
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        $n = 0
        if ([int]::TryParse($answer, [ref]$n) -and $n -ge 1 -and $n -le $Options.Count) {
            return $n
        }
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
    } catch {
        return $false
    }
}

function Invoke-Elevated {
    param([string]$Path, [string]$Language)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $ScriptPath), '-Elevated')
    if ($Path) { $argList += @('-GamePath', ('"{0}"' -f $Path)) }
    if ($Language) { $argList += @('-Lang', $Language) }
    if ($NoShortcut) { $argList += '-NoShortcut' }
    if ($Shortcut) { $argList += '-Shortcut' }
    if ($Force) { $argList += '-Force' }
    if ($Pause) { $argList += '-Pause' }
    Write-Host 'Требуются права администратора. Запрашиваю UAC...' -ForegroundColor Yellow
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs -Wait -PassThru
        exit $proc.ExitCode
    } catch {
        Write-Host 'Не удалось получить права администратора. Установка отменена.' -ForegroundColor Red
        exit 1
    }
}

function Get-GameVersionLine {
    $logPath = Join-Path $env:USERPROFILE 'Documents\My Games\Binding of Isaac Rebirth\log.txt'
    if (-not (Test-Path -LiteralPath $logPath)) { return $null }
    try {
        $lines = Get-Content -LiteralPath $logPath -ErrorAction Stop
        $match = $lines | Select-String -Pattern 'Binding of Isaac:' | Select-Object -Last 1
        if ($match) { return $match.Line.Trim() }
    } catch {
        return $null
    }
    return $null
}

function Add-UniqueLibrary {
    param(
        [string]$Path,
        [System.Collections.Generic.HashSet[string]]$Seen,
        [System.Collections.Generic.List[string]]$Result
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $normalized = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    } catch {
        return
    }
    if ($Seen.Add($normalized)) { $Result.Add($normalized) }
}

function Get-SteamLibraries {
    $libs = New-Object System.Collections.Generic.List[string]
    $keys = @(
        @{ Path = 'HKCU:\Software\Valve\Steam'; Name = 'SteamPath' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam'; Name = 'InstallPath' },
        @{ Path = 'HKLM:\SOFTWARE\Valve\Steam'; Name = 'InstallPath' }
    )
    foreach ($key in $keys) {
        try {
            $props = Get-ItemProperty -Path $key.Path -ErrorAction Stop
            $p = $props.($key.Name)
            if ($p) {
                $p = $p -replace '/', '\'
                $libs.Add($p)
            }
        } catch { }
    }
    foreach ($default in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam', 'D:\Steam', 'D:\SteamLibrary', 'E:\Steam', 'E:\SteamLibrary')) {
        if (Test-Path -LiteralPath $default -PathType Container) { $libs.Add($default) }
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($lib in $libs) {
        Add-UniqueLibrary -Path $lib -Seen $seen -Result $result
        $vdf = Join-Path $lib 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $vdf)) { continue }
        try {
            $content = Get-Content -LiteralPath $vdf -Raw -ErrorAction Stop
            foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                Add-UniqueLibrary -Path $p -Seen $seen -Result $result
            }
            foreach ($m in [regex]::Matches($content, '(?m)^\s*"\d+"\s+"([^"]+)"')) {
                $p = $m.Groups[1].Value -replace '\\\\', '\'
                Add-UniqueLibrary -Path $p -Seen $seen -Result $result
            }
        } catch { }
    }
    return $result
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

function Find-GameCandidates {
    $candidates = New-Object System.Collections.Generic.List[string]
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($lib in @(Get-SteamLibraries)) {
        $p = Join-Path $lib 'steamapps\common\The Binding of Isaac Rebirth'
        $resolved = Resolve-GamePath $p
        if ($resolved -and $seen.Add($resolved)) { $candidates.Add($resolved) }
    }
    return $candidates
}

function Get-GamePathInteractive {
    param([string]$Provided)
    if ($Provided) {
        $resolved = Resolve-GamePath $Provided
        if (-not $resolved) {
            throw "Указанный путь не похож на папку игры Rebirth (нет isaac-ng.exe или resources): $Provided"
        }
        return $resolved
    }

    $candidates = @(Find-GameCandidates)
    if ($candidates.Count -eq 1) { return $candidates[0] }
    if ($candidates.Count -gt 1) {
        $choice = Read-Choice 'Найдено несколько установок игры. Выберите нужную:' $candidates 1
        return $candidates[$choice - 1]
    }

    Write-Host 'Не удалось автоматически найти The Binding of Isaac: Rebirth.' -ForegroundColor Yellow
    Write-Host 'Обычно папка игры находится здесь:' -ForegroundColor DarkGray
    Write-Host '  C:\Program Files (x86)\Steam\steamapps\common\The Binding of Isaac Rebirth' -ForegroundColor DarkGray
    while ($true) {
        $answer = Read-Host 'Введите путь к папке игры (или q для выхода)'
        if ($answer -eq 'q' -or $answer -eq 'Q') { exit 1 }
        $resolved = Resolve-GamePath $answer
        if ($resolved) { return $resolved }
        Write-Host 'В этой папке нет isaac-ng.exe и resources. Проверьте путь.' -ForegroundColor Yellow
    }
}

function Assert-SafeRelativePath {
    param([string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw 'Пустой путь в payload.' }
    if ([System.IO.Path]::IsPathRooted($RelativePath)) { throw "Абсолютный путь в payload: $RelativePath" }
    $parts = $RelativePath -split '[\\/]'
    if ($parts -contains '..') { throw "Недопустимый путь в payload: $RelativePath" }
    if ($RelativePath -notmatch '^(gfx\\|animations\.b$|pocketitems\.xml$)') {
        throw "Неожиданный файл в payload: $RelativePath"
    }
}

function Assert-SafeChildPath {
    param([string]$Root, [string]$Child)
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $childFull = [System.IO.Path]::GetFullPath($Child)
    if (-not $childFull.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Путь вне папки игры: $Child"
    }
}

function Get-PayloadFiles {
    param([string]$Root)
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        throw "Не найдена папка payload: $Root"
    }
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    Get-ChildItem -LiteralPath $rootFull -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($rootFull.Length).TrimStart('\')
        [PSCustomObject]@{
            RelativePath = $rel
            SourcePath = $_.FullName
            Length = $_.Length
        }
    }
}

function Get-FileSha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} ГБ' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} МБ' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} КБ' -f ($Bytes / 1KB)) }
    return "$Bytes Б"
}

function Get-InstallPlan {
    param([string]$Game, [string]$Language)
    $sources = @{}
    foreach ($file in @(Get-PayloadFiles $EidPayload)) {
        Assert-SafeRelativePath $file.RelativePath
        $sources[$file.RelativePath.ToLowerInvariant()] = $file
    }
    if ($Language -eq 'ru') {
        if (-not (Test-Path -LiteralPath $RuPayload -PathType Container)) {
            throw "Не найдена папка русских описаний: $RuPayload"
        }
        foreach ($file in @(Get-PayloadFiles $RuPayload)) {
            Assert-SafeRelativePath $file.RelativePath
            $sources[$file.RelativePath.ToLowerInvariant()] = $file
        }
    }

    $resourcesRoot = Join-Path $Game 'resources'
    $plan = New-Object System.Collections.Generic.List[object]
    foreach ($key in ($sources.Keys | Sort-Object)) {
        $src = $sources[$key]
        $relativeTarget = Join-Path 'resources' $src.RelativePath
        $target = Join-Path $Game $relativeTarget
        Assert-SafeChildPath $Game $target
        $plan.Add([PSCustomObject]@{
            Path = $relativeTarget
            SourcePath = $src.SourcePath
            Length = $src.Length
            Action = 'created'
            Sha256 = $null
            BackupRel = $null
            BackupSha256 = $null
        })
    }
    return $plan
}

function Set-PlanActions {
    param(
        $Plan,
        [string]$Game,
        [string]$BackupRoot,
        [switch]$DryRun
    )
    $counts = [ordered]@{ created = 0; replaced = 0; preexisting = 0; total = $Plan.Count; bytes = [long]0 }
    $backupUsed = $false
    $i = 0
    foreach ($rec in $Plan) {
        $i++
        $target = Join-Path $Game $rec.Path
        Assert-SafeChildPath $Game $target
        $rec.Sha256 = Get-FileSha256 $rec.SourcePath
        $counts.bytes += [long]$rec.Length

        if (Test-Path -LiteralPath $target) {
            if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
                throw "На месте файла находится папка: $target"
            }
            $item = Get-Item -LiteralPath $target
            if ($item.Length -eq $rec.Length) {
                $targetHash = Get-FileSha256 $target
                if ($targetHash -eq $rec.Sha256) {
                    $rec.Action = 'preexisting'
                    $counts.preexisting++
                    continue
                }
            }
            $rec.Action = 'replaced'
            $rec.BackupRel = $rec.Path
            $backupUsed = $true
            if (-not $DryRun) {
                $backupPath = Join-Path $BackupRoot $rec.BackupRel
                $backupParent = Split-Path -Parent $backupPath
                if (-not (Test-Path -LiteralPath $backupParent)) {
                    New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
                }
                Copy-Item -LiteralPath $target -Destination $backupPath -Force
                $rec.BackupSha256 = Get-FileSha256 $backupPath
            }
            $counts.replaced++
        } else {
            $rec.Action = 'created'
            $counts.created++
        }

        if ($i % 100 -eq 0) {
            Write-Progress -Activity 'Проверка файлов' -Status ("{0} / {1}" -f $i, $Plan.Count) -PercentComplete (($i / [double]$Plan.Count) * 100)
        }
    }
    Write-Progress -Activity 'Проверка файлов' -Completed
    return [PSCustomObject]@{ Counts = $counts; BackupUsed = $backupUsed }
}

function Invoke-CopyPlan {
    param($Plan, [string]$Game)
    $i = 0
    foreach ($rec in $Plan) {
        $i++
        if ($rec.Action -eq 'preexisting') { continue }
        $target = Join-Path $Game $rec.Path
        $parent = Split-Path -Parent $target
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $rec.SourcePath -Destination $target -Force
        if ($i % 50 -eq 0 -or $i -eq $Plan.Count) {
            Write-Progress -Activity 'Установка EID' -Status ("{0} / {1}" -f $i, $Plan.Count) -PercentComplete (($i / [double]$Plan.Count) * 100)
        }
    }
    Write-Progress -Activity 'Установка EID' -Completed

    Write-Host 'Проверка контрольных сумм...' -ForegroundColor DarkGray
    $j = 0
    foreach ($rec in $Plan) {
        $j++
        if ($rec.Action -eq 'preexisting') { continue }
        $target = Join-Path $Game $rec.Path
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
            throw "Файл не скопирован: $($rec.Path)"
        }
        $hash = Get-FileSha256 $target
        if ($hash -ne $rec.Sha256) {
            throw "Контрольная сумма не совпала: $($rec.Path)"
        }
        if ($j % 100 -eq 0) {
            Write-Progress -Activity 'Проверка' -Status ("{0} / {1}" -f $j, $Plan.Count) -PercentComplete (($j / [double]$Plan.Count) * 100)
        }
    }
    Write-Progress -Activity 'Проверка' -Completed
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

function Invoke-Rollback {
    param($Plan, [string]$Game, [string]$BackupRoot)
    Write-Host 'Откат изменений...' -ForegroundColor Yellow
    foreach ($rec in @($Plan | Sort-Object { $_.Path.Length } -Descending)) {
        $target = Join-Path $Game $rec.Path
        try {
            if ($rec.Action -eq 'created') {
                if (Test-Path -LiteralPath $target -PathType Leaf) {
                    Remove-Item -LiteralPath $target -Force
                }
            } elseif ($rec.Action -eq 'replaced') {
                $backup = Join-Path $BackupRoot $rec.BackupRel
                if (Test-Path -LiteralPath $backup -PathType Leaf) {
                    $parent = Split-Path -Parent $target
                    if (-not (Test-Path -LiteralPath $parent)) {
                        New-Item -ItemType Directory -Path $parent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $backup -Destination $target -Force
                } else {
                    Write-Warning "Резервная копия не найдена: $backup"
                }
            }
        } catch {
            Write-Warning "Не удалось откатить $($rec.Path): $($_.Exception.Message)"
        }
    }
    Remove-EmptyDirectories (Join-Path $Game 'resources')
}

function Install-Hud {
    param([string]$Source, [string]$Target, [string]$Shortcut, [bool]$CreateShortcut)
    if (Test-Path -LiteralPath $Target) {
        Remove-Item -LiteralPath $Target -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    Copy-Item -Path (Join-Path $Source '*') -Destination $Target -Recurse -Force

    $prefsLines = @(
        '[General]',
        'show_tears_fired=false',
        'show_shot_height=false',
        'split_deal_chance=false',
        'stat_precision=2'
    )
    [System.IO.File]::WriteAllText((Join-Path $Target 'MHUD2.prefs'), (($prefsLines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))

    if ($CreateShortcut -and $Shortcut) {
        $shell = New-Object -ComObject WScript.Shell
        $lnk = $shell.CreateShortcut($Shortcut)
        $lnk.TargetPath = Join-Path $Target 'START_HUD.bat'
        $lnk.WorkingDirectory = $Target
        $lnk.IconLocation = (Join-Path $Target 'MissingHUD2.exe') + ',0'
        $lnk.Description = 'MissingHUD2 - статистика персонажа для Isaac Rebirth'
        $lnk.Save()
    }
    return $Target
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

function Save-State {
    param($State)
    if (-not (Test-Path -LiteralPath $StateRoot)) {
        New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
    }
    $json = $State | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($StatePath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Wait-GameClosed {
    if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Warning 'Игра сейчас запущена. Перед установкой её нужно закрыть.'
            return
        }
        Write-Host 'Игра сейчас запущена.' -ForegroundColor Yellow
        if ($Force) { throw 'Закройте The Binding of Isaac: Rebirth и повторите установку.' }
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
            Write-Warning 'MissingHUD2 сейчас запущен. Перед установкой его нужно закрыть.'
            return
        }
        Write-Host 'MissingHUD2 сейчас запущен.' -ForegroundColor Yellow
        if ($Force) { throw 'Закройте MissingHUD2 и повторите установку.' }
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

    if (Test-Path -LiteralPath $StatePath) {
        $prev = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        Write-Host 'Обнаружена предыдущая установка этого набора.' -ForegroundColor Yellow
        if ($prev.installedAt) { Write-Host ("Дата установки: {0}" -f $prev.installedAt) }
        if ($prev.gamePath) { Write-Host ("Папка игры: {0}" -f $prev.gamePath) }
        Write-Host ''
        Write-Host 'Сначала запустите UNINSTALL.bat, затем установите заново.' -ForegroundColor Yellow
        Write-Host 'Так вы сможете сменить язык описаний и корректно восстановить файлы.'
        exit 1
    }

    if (-not $Lang) {
        $choice = Read-Choice 'Выберите язык описаний предметов:' @(
            'Русский (рекомендуется) - русские описания на картинках',
            'English - оригинальные английские описания EID'
        ) 1
        $Lang = if ($choice -eq 1) { 'ru' } else { 'en' }
    } else {
        $Lang = $Lang.ToLowerInvariant()
    }

    Write-Step 1 6 'Поиск игры'
    $game = Get-GamePathInteractive $GamePath
    Write-Host ("Папка игры: {0}" -f $game) -ForegroundColor Green
    $versionLine = Get-GameVersionLine
    if ($versionLine) {
        Write-Host ("Версия: {0}" -f $versionLine)
    } else {
        Write-Host 'Версию определить не удалось (log.txt не найден).' -ForegroundColor Yellow
    }
    if ($versionLine -and $versionLine -match '(?i)afterbirth|repentance') {
        Write-Host ''
        Write-Warning 'Похоже, установлен DLC Afterbirth/Afterbirth+/Repentance.'
        Write-Warning 'Этот набор предназначен для базовой Rebirth без DLC.'
        if (-not $DryRun) {
            $choice = Read-Choice 'Продолжить всё равно?' @('Нет, выйти', 'Да, продолжить') 1
            if ($choice -eq 1) { exit 1 }
        }
    }

    if (-not $DryRun -and -not (Test-WriteAccess $game) -and -not (Test-IsAdmin)) {
        Invoke-Elevated -Path $game -Language $Lang
    }
    if (-not $DryRun -and -not (Test-WriteAccess $game)) {
        throw 'Нет прав на запись в папку игры. Запустите INSTALL.bat от имени администратора.'
    }

    Wait-GameClosed
    Wait-HudClosed

    Write-Step 2 6 'Подготовка списка файлов'
    $plan = @(Get-InstallPlan -Game $game -Language $Lang)
    if ($plan.Count -eq 0) { throw 'В payload не найдено файлов для установки.' }
    Write-Host ("Файлов: {0}" -f $plan.Count)
    Write-Host ("Язык описаний: {0}" -f $(if ($Lang -eq 'ru') { 'русский' } else { 'English' }))

    $createShortcut = -not $NoShortcut
    if ($Shortcut) { $createShortcut = $true }
    if ($Shortcut -and $NoShortcut) {
        throw 'Нельзя одновременно указывать -Shortcut и -NoShortcut.'
    }
    if (-not $DryRun -and -not $NoShortcut -and -not $Shortcut -and $ShortcutPath) {
        $choice = Read-Choice 'Создать ярлык на рабочем столе для запуска HUD?' @('Да', 'Нет') 1
        $createShortcut = ($choice -eq 1)
    }
    if (-not $ShortcutPath) { $createShortcut = $false }

    Write-Step 3 6 'Проверка файлов и резервное копирование'
    $backupRoot = Join-Path $BackupRootBase (Get-Date -Format 'yyyyMMdd_HHmmss')
    $planResult = Set-PlanActions -Plan $plan -Game $game -BackupRoot $backupRoot -DryRun:$DryRun
    $counts = $planResult.Counts
    Write-Host ("Новых файлов: {0}" -f $counts.created)
    Write-Host ("Будет заменено (с резервной копией): {0}" -f $counts.replaced)
    Write-Host ("Уже совпадает (не трогаем): {0}" -f $counts.preexisting)
    Write-Host ("Общий размер: {0}" -f (Format-Size $counts.bytes))
    if ($planResult.BackupUsed) {
        if ($DryRun) {
            Write-Host ("Будут созданы резервные копии: {0}" -f $backupRoot)
        } else {
            Write-Host ("Резервные копии: {0}" -f $backupRoot)
        }
    } else {
        Write-Host 'Существующих файлов для резервного копирования нет.'
    }

    if ($DryRun) {
        Write-Host ''
        Write-Host 'DRYRUN: изменения не вносятся.' -ForegroundColor Yellow
        Write-Host ("HUD будет установлен в: {0}" -f $HudInstallDir)
        if ($createShortcut) { Write-Host ("Ярлык: {0}" -f $ShortcutPath) } else { Write-Host 'Ярлык создавать не будем.' }
        Write-Host ''
        Write-Host 'Проверка завершена.' -ForegroundColor Green
        exit 0
    }

    Write-Step 4 6 'Установка MissingHUD2'
    $hudInstalled = $false
    try {
        $hudResult = Install-Hud -Source $HudPayload -Target $HudInstallDir -Shortcut $ShortcutPath -CreateShortcut $createShortcut
        $hudInstalled = $true
        Write-Host ("HUD установлен: {0}" -f $hudResult) -ForegroundColor Green
        if ($createShortcut) { Write-Host ("Ярлык: {0}" -f $ShortcutPath) -ForegroundColor Green }
    } catch {
        throw ("Не удалось установить HUD: {0}" -f $_.Exception.Message)
    }

    Write-Step 5 6 'Установка EID в resources'
    try {
        Invoke-CopyPlan -Plan $plan -Game $game
    } catch {
        $copyError = $_.Exception.Message
        Write-Host ("Ошибка установки: {0}" -f $copyError) -ForegroundColor Red
        Invoke-Rollback -Plan $plan -Game $game -BackupRoot $backupRoot
        if ($hudInstalled) {
            try { Remove-Hud -Target $HudInstallDir -Shortcut $(if ($createShortcut) { $ShortcutPath } else { $null }) } catch { }
        }
        throw ("Установка отменена, изменения откачены. Резервные копии: {0}" -f $backupRoot)
    }

    $state = [ordered]@{
        kitVersion = $KitVersion
        installedAt = (Get-Date).ToString('o')
        gamePath = $game
        language = $Lang
        backupDir = $(if ($planResult.BackupUsed) { $backupRoot } else { $null })
        files = @($plan)
        hud = [ordered]@{
            dir = $HudInstallDir
            exe = (Join-Path $HudInstallDir 'MissingHUD2.exe')
            shortcut = $(if ($createShortcut) { $ShortcutPath } else { $null })
        }
    }
    Save-State $state
    Write-Host ("Состояние установки сохранено: {0}" -f $StatePath) -ForegroundColor DarkGray

    Write-Step 6 6 'Готово'
    Write-Host ''
    Write-Host 'Установка завершена.' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Что дальше:' -ForegroundColor White
    Write-Host '  1. Запустите The Binding of Isaac: Rebirth.'
    Write-Host '  2. Подойдите к предмету - описание появится на картинке предмета.'
    Write-Host '  3. Войдите в забег и запустите HUD:'
    if ($createShortcut) {
        Write-Host ("     ярлык на рабочем столе: {0}" -f $ShortcutPath)
        Write-Host ("     или: {0}" -f (Join-Path $HudInstallDir 'START_HUD.bat'))
    } else {
        Write-Host ("     {0}" -f (Join-Path $HudInstallDir 'START_HUD.bat'))
    }
    Write-Host '  4. Если HUD не появляется, запустите START_HUD_ADMIN.bat от администратора.'
    Write-Host ''
    Write-Host 'Удаление: UNINSTALL.bat (восстановит резервные копии).' -ForegroundColor DarkGray
    Write-Host ("Резервные копии: {0}" -f $(if ($planResult.BackupUsed) { $backupRoot } else { 'не требовались' })) -ForegroundColor DarkGray
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
