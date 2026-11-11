# build_windows.ps1 - 버전을 올리고 Windows 릴리스 빌드
#   기본: 패치 +1 (1.12.0+15 -> 1.12.1+16) · -Minor: 마이너 +1 (1.13.0+16) · -NoBump: 그대로
#   결과: build\windows\x64\runner\Release\locationx_position_setting_tool_vX.Y.Z.exe
param([switch]$Minor, [switch]$NoBump)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pubspec = Join-Path $root 'pubspec.yaml'

$text = [System.IO.File]::ReadAllText($pubspec)
$m = [regex]::Match($text, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $m.Success) { throw 'pubspec.yaml에서 version: X.Y.Z+N 을 찾지 못함' }
$maj = [int]$m.Groups[1].Value; $min = [int]$m.Groups[2].Value
$pat = [int]$m.Groups[3].Value; $bld = [int]$m.Groups[4].Value
$old = "$maj.$min.$pat+$bld"

if (-not $NoBump) {
    if ($Minor) { $min++; $pat = 0 } else { $pat++ }
    $bld++
    $new = "$maj.$min.$pat+$bld"
    $text = $text.Remove($m.Index, $m.Length).Insert($m.Index, "version: $new")
    # BOM 없는 UTF-8 유지
    [System.IO.File]::WriteAllText($pubspec, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "버전 $old -> $new"
} else {
    $new = $old
    Write-Host "버전 유지 $old"
}

Push-Location $root
try {
    flutter build windows
    if ($LASTEXITCODE -ne 0) { throw "flutter build 실패 (exit $LASTEXITCODE) - 도구가 실행 중이면 닫고 다시" }
} finally { Pop-Location }

$exe = Join-Path $root ("build\windows\x64\runner\Release\locationx_position_setting_tool_v{0}.{1}.{2}.exe" -f $maj, $min, $pat)
if (Test-Path $exe) { Write-Host "완료: $exe" } else { Write-Host "빌드는 끝났지만 $exe 가 없음" }
