<#
  银色幻想 (Silver) 简体中文汉化补丁 —— 安装 / 卸载 / 检查
  无需 Python，仅用 Windows 自带的 PowerShell。

  用法:
    powershell -ExecutionPolicy Bypass -File install.ps1 install
    powershell -ExecutionPolicy Bypass -File install.ps1 uninstall
    powershell -ExecutionPolicy Bypass -File install.ps1 status
    powershell -ExecutionPolicy Bypass -File install.ps1 install -GameDir "D:\Games\Silver"

  也可直接双击同目录下的「安装汉化.bat」「卸载汉化.bat」。
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)]
  [ValidateSet('install', 'uninstall', 'status')]
  [string]$Action = 'status',
  [string]$GameDir = '',
  # 文本版本：latin = 人名原文版（默认），zh = 人名中文版
  [ValidateSet('latin', 'zh')]
  [string]$Variant = ''
)

$ErrorActionPreference = 'Stop'
$Root    = $PSScriptRoot
$Payload = Join-Path $Root 'payload'
$BakName = '_zh_patch_backup'
$VariantFile = Join-Path $Root 'variant.txt'

function Resolve-Variant {
  if ($Variant -eq 'zh' -or $Variant -eq 'latin') { return $Variant }
  if (Test-Path -LiteralPath $VariantFile) {
    $v = (Get-Content -LiteralPath $VariantFile -First 1).Trim().ToLower()
    if ($v -eq 'zh' -or $v -eq 'latin') { return $v }
  }
  $man = Join-Path (Join-Path (Resolve-Path '.').Path '_zh_patch_backup') 'manifest.json'
  return 'latin'
}

function Get-PayloadDir {
  # 基础层永远是 payload；人名中文版额外叠加 payload_zh（覆盖层，见 Get-PayloadFiles）
  return (Join-Path $Root 'payload')
}

# 本补丁适配的 silver.exe 版本（3,024,384 字节）
$OrigSha    = '072e5d9c174346a5be68c82e5f917871c20f253bb3efa78a4bdb697401dbbc3a'
$PatchedSha = 'a629aacdc2cfc8fa8e5e0dcc0d51ed4a88ec1c428284bdc1da9309661d0f8277'
# 旧版补丁打出来的 silver.exe（v1.2），升级时同样放行，避免多余的警告
$PatchedShaOld = 'acbdc9809149d854974160e00ecd1e8f81b4ba64f1d7a2689dc4647a59b40914'
$PatchedShaOld2 = 'd670f51e32aa5bd17d10145e389cb7e9bcf6fecbbbbcce2bb4e7795f393afded'
$PatchedShaOld4 = 'c91a88d138b3ac48aa2744cbff50c40d9c8efc7b9b5b377e149dd9d3e696f6a5'
$PatchedShaOld3 = '03feec362f981f238745b3e1a65a88d56156788817ba5fa174c63ef6b120bfd5'
# 人名中文版（渲染期替换）用的 silver.exe
$PatchedShaZh  = '57f32e7596bc73f6ec1313ec197f0ac578251b6f8d78ac83af7a2ec006d2f535'

function Fail($msg) { Write-Host "错误: $msg" -ForegroundColor Red; exit 1 }

function Resolve-GameDir {
  if ($GameDir -ne '') {
    if (Test-Path (Join-Path $GameDir 'silver.exe')) { return (Resolve-Path $GameDir).Path }
    Fail "指定的游戏目录里没有 silver.exe: $GameDir"
  }
  $cfg = Join-Path $Root 'gamedir.txt'
  if (Test-Path $cfg) {
    $p = (Get-Content $cfg -First 1).Trim()
    if ($p -ne '' -and (Test-Path (Join-Path $p 'silver.exe'))) { return (Resolve-Path $p).Path }
  }
  $guesses = @(
    'E:\SteamLibrary\steamapps\common\Silver',
    'D:\SteamLibrary\steamapps\common\Silver',
    'C:\Program Files (x86)\Steam\steamapps\common\Silver',
    'C:\Program Files\Steam\steamapps\common\Silver'
  )
  foreach ($g in $guesses) { if (Test-Path (Join-Path $g 'silver.exe')) { return $g } }
  # 从 Steam 的 libraryfolders.vdf 里找
  foreach ($steam in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam')) {
    $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
      foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
        $cand = Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common\Silver'
        if (Test-Path (Join-Path $cand 'silver.exe')) { return $cand }
      }
    }
  }
  Fail "找不到银色幻想游戏目录，请用 -GameDir 指定，或把路径写进同目录的 gamedir.txt"
}

function Get-Sha($path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLower() }

function Get-PayloadFiles {
  $Payload = Get-PayloadDir
  if (-not (Test-Path -LiteralPath $Payload)) { Fail "找不到 payload 目录: $Payload" }
  $dirs = @($Payload)
  if ((Resolve-Variant) -eq 'zh') {
    $ov = Join-Path $Root 'payload_zh'
    if (Test-Path -LiteralPath $ov) { $dirs += $ov }   # 覆盖层：同名文件以后者为准
  }
  $map = [ordered]@{}
  foreach ($d in $dirs) {
    $full = (Resolve-Path $d).Path
    foreach ($f in Get-ChildItem -LiteralPath $d -Recurse -File) {
      $rel = $f.FullName.Substring($full.Length).TrimStart('\')
      $map[$rel.ToLower()] = [pscustomobject]@{ rel = $rel; src = $f.FullName }
    }
  }
  return ($map.Values | Sort-Object rel)
}

function Do-Install($game) {
  $bak      = Join-Path $game $BakName
  $manifest = Join-Path $bak 'manifest.json'
  if (Test-Path $manifest) {
    $old = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($old.files.Count -gt 0) {
      Fail "检测到上次安装尚未卸载（$manifest）。请先运行卸载，再重新安装。"
    }
  }
  $files = Get-PayloadFiles
  Write-Host "游戏目录: $game"
  Write-Host "文本版本: $(if ((Resolve-Variant) -eq 'zh') { '人名中文版' } else { '人名英文版' })"
  Write-Host "补丁文件: $($files.Count) 个"

  # 版本校验：确认游戏目录里的 silver.exe 是本补丁适配的那个版本
  $exe = Join-Path $game 'silver.exe'
  if (Test-Path -LiteralPath $exe) {
    $h = Get-Sha $exe
    if ($h -ne $OrigSha -and $h -ne $PatchedSha -and $h -ne $PatchedShaOld -and $h -ne $PatchedShaOld2 -and $h -ne $PatchedShaOld3 -and $h -ne $PatchedShaOld4 -and $h -ne $PatchedShaOld5 -and $h -ne $PatchedShaOld6 -and $h -ne $PatchedShaZh) {
      Write-Host ""
      Write-Host "!! 警告：游戏目录里的 silver.exe 不是本补丁适配的版本。" -ForegroundColor Yellow
      Write-Host "   期望（原版）  : $OrigSha"
      Write-Host "   期望（已打补丁）: $PatchedSha"
      Write-Host "   实际          : $h"
      Write-Host "   继续安装会用补丁自带的 silver.exe 覆盖它，可能不兼容。"
      Write-Host "   若游戏刚被 Steam 更新过，建议先在 Steam 里「验证游戏文件完整性」。"
      Write-Host ""
      $ans = ''
      try { $ans = Read-Host "仍要继续吗？输入 y 再回车继续，直接回车取消" } catch { $ans = '' }
      if ($ans -ne 'y' -and $ans -ne 'Y') { Fail "已取消，未修改任何文件。" }
    }
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $bak 'orig') | Out-Null

  $records = @()
  $nOver = 0; $nNew = 0
  foreach ($f in $files) {
    $dst = Join-Path $game $f.rel
    $existed = Test-Path -LiteralPath $dst
    $rec = [ordered]@{ rel = $f.rel; existed = $existed }
    if ($existed) {
      $nOver++
      $rec.orig_sha  = Get-Sha $dst
      $rec.orig_size = (Get-Item -LiteralPath $dst).Length
      $bkp = Join-Path (Join-Path $bak 'orig') $f.rel
      New-Item -ItemType Directory -Force -Path (Split-Path $bkp -Parent) | Out-Null
      Copy-Item -LiteralPath $dst -Destination $bkp -Force
    } else {
      $nNew++
      New-Item -ItemType Directory -Force -Path (Split-Path $dst -Parent) | Out-Null
    }
    Copy-Item -LiteralPath $f.src -Destination $dst -Force
    $rec.new_sha = Get-Sha $dst
    $records += [pscustomobject]$rec
  }
  $manifestObj = [ordered]@{
    when  = (Get-Date).ToString('s')
    game  = $game
    variant = (Resolve-Variant)
    files = $records
  }
  # 写成不带 BOM 的 UTF-8，这样 Python 版安装器也能直接读（utf-8-sig 两边都兼容）
  $json = $manifestObj | ConvertTo-Json -Depth 6
  [System.IO.File]::WriteAllText($manifest, $json, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "安装完成: 覆盖 $nOver 个，新建 $nNew 个。" -ForegroundColor Green
  Write-Host "原文件已备份到: $bak\orig"
  Write-Host "启动游戏即为简体中文（第一次启动会先播开场动画）。"
  Write-Host "如需还原，运行「卸载汉化.bat」。"
}

function Do-Uninstall($game) {
  $bak      = Join-Path $game $BakName
  $manifest = Join-Path $bak 'manifest.json'
  if (-not (Test-Path $manifest)) { Fail "没有找到安装记录（$manifest），无法卸载。" }
  $man = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
  $restored = 0; $removed = 0; $mismatch = 0
  $dirs = @()
  foreach ($rec in $man.files) {
    $dst = Join-Path $game $rec.rel
    if ($rec.existed) {
      $bkp = Join-Path (Join-Path $bak 'orig') $rec.rel
      if (Test-Path -LiteralPath $bkp) {
        Copy-Item -LiteralPath $bkp -Destination $dst -Force
        if ((Get-Sha $dst) -ne $rec.orig_sha) {
          Write-Host "!! 还原后校验不符: $($rec.rel)" -ForegroundColor Yellow; $mismatch++
        }
        $restored++
      } else {
        Write-Host "!! 备份缺失，跳过: $($rec.rel)" -ForegroundColor Yellow
      }
    } else {
      if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force; $removed++ }
    }
    $dirs += (Split-Path $dst -Parent)
  }
  # 清理变空的目录：收集所有涉及的目录及其全部祖先，按路径长度从深到浅尝试删除。
  # 注意 languages\chinese\silver\levels 这类目录只含子目录、不含文件，
  # 所以必须沿祖先链向上收集，不能只用 Split-Path 的父目录。
  $allDirs = New-Object System.Collections.Generic.List[string]
  foreach ($rec in $man.files) {
    $p = Split-Path (Join-Path $game $rec.rel) -Parent
    while ($p -and $p.Length -gt $game.Length -and $p -ne $game) {
      if (-not $allDirs.Contains($p)) { $allDirs.Add($p) }
      $p = Split-Path $p -Parent
    }
  }
  $allDirs | Sort-Object -Property Length -Descending | ForEach-Object {
    # 非空目录会抛异常，直接忽略 —— 这正好实现"只删空目录"
    try { [System.IO.Directory]::Delete($_, $false) } catch { }
  }
  Remove-Item -LiteralPath $bak -Recurse -Force
  Write-Host "卸载完成: 还原 $restored 个，删除 $removed 个。" -ForegroundColor Green
  if ($mismatch -gt 0) { Write-Host "有 $mismatch 个文件还原后校验不符，请用 Steam 校验游戏文件完整性。" -ForegroundColor Yellow }
}

function Do-Status($game) {
  $bak      = Join-Path $game $BakName
  $manifest = Join-Path $bak 'manifest.json'
  Write-Host "游戏目录: $game"
  if (-not (Test-Path $manifest)) { Write-Host "未安装（没有安装记录）。"; return }
  $man = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
  Write-Host "安装时间: $($man.when)"
  if ($man.variant) { Write-Host "文本版本: $(if ($man.variant -eq 'zh') { '人名中文版' } else { '人名英文版' })" }
  Write-Host "记录文件: $($man.files.Count) 个"
  $changed = 0
  foreach ($rec in $man.files) {
    $dst = Join-Path $game $rec.rel
    if (-not (Test-Path -LiteralPath $dst)) {
      Write-Host "缺失: $($rec.rel)" -ForegroundColor Yellow; $changed++
    } elseif ((Get-Sha $dst) -ne $rec.new_sha) {
      Write-Host "已被改动: $($rec.rel)" -ForegroundColor Yellow; $changed++
    }
  }
  if ($changed -eq 0) { Write-Host "状态: 已安装，所有文件与安装时一致。" -ForegroundColor Green }
  else { Write-Host "状态: 已安装，但有 $changed 个文件与安装时不一致。" -ForegroundColor Yellow }
}

$game = Resolve-GameDir
switch ($Action) {
  'install'   { Do-Install   $game }
  'uninstall' { Do-Uninstall $game }
  'status'    { Do-Status    $game }
}
