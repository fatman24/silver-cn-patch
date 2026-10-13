# 银色幻想 (Silver) 简体中文汉化补丁 —— 图形安装器
# PowerShell + WinForms，零依赖。由 fatman-24 制作。
# 说明：所有子进程都用 -WindowStyle Hidden；窗口先显示、再做状态自检。
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Continue'
$Root    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Inst    = Join-Path $Root 'install.ps1'
$GameTxt = Join-Path $Root 'gamedir.txt'
$VarTxt  = Join-Path $Root 'variant.txt'
$BakName = '_zh_patch_backup'
$PSARGS  = @('-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass')
# 单实例保护：避免重复启动留下看不见的残留进程（会占住文件夹）
$script:mutex = New-Object System.Threading.Mutex($false, 'Local\SilverZhPatchGuiMutex')
$script:isFirst = $false
try { $script:isFirst = $script:mutex.WaitOne(0) } catch { $script:isFirst = $true }
if (-not $script:isFirst) {
    [void][System.Windows.Forms.MessageBox]::Show('汉化安装器已经在运行中。' + [char]10 + [char]10 +
        '请看任务栏（或在窗口列表里找「《银色幻想》简体中文汉化补丁」），' + [char]10 +
        '不要重复打开 —— 重复打开会留下占用文件夹的后台进程。', '提示', 'OK', 'Information')
    exit
}

$LogFile = Join-Path $Root 'gui_log.txt'
function Write-Boot([string]$m) {
    try { ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) | Out-File -FilePath $LogFile -Append -Encoding utf8 } catch { }
}
Write-Boot ('GUI 启动  pid=' + $PID + '  PSVersion=' + $PSVersionTable.PSVersion)

# ---------------------------------------------------------------- 主题
$C_BG      = [System.Drawing.Color]::FromArgb(246, 242, 234)
$C_HEAD    = [System.Drawing.Color]::FromArgb(58, 41, 24)
$C_HEADTXT = [System.Drawing.Color]::FromArgb(244, 232, 205)
$C_CARD    = [System.Drawing.Color]::White
$C_BTN1    = [System.Drawing.Color]::FromArgb(233, 224, 208)
$C_BTN2    = [System.Drawing.Color]::FromArgb(206, 226, 208)
$C_BTN3    = [System.Drawing.Color]::FromArgb(240, 224, 206)
$C_TEXT    = [System.Drawing.Color]::FromArgb(48, 38, 28)
$C_OK      = [System.Drawing.Color]::FromArgb(34, 120, 60)
$C_WARN    = [System.Drawing.Color]::FromArgb(176, 96, 24)
$C_OFF     = [System.Drawing.Color]::FromArgb(120, 120, 120)

# ---------------------------------------------------------------- 工具
function Find-SteamGame {
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($k in @('HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam')) {
        try {
            $p = Get-ItemProperty -Path $k -ErrorAction Stop
            foreach ($n in @('SteamPath', 'InstallPath')) { if ($p.$n) { $paths.Add(($p.$n -replace '/', '\')) } }
        } catch { }
    }
    foreach ($p in @('C:\Program Files (x86)\Steam', 'C:\Program Files\Steam', 'D:\Steam', 'E:\Steam')) { $paths.Add($p) }
    $libs = New-Object System.Collections.Generic.List[string]
    foreach ($s in $paths) {
        if (Test-Path (Join-Path $s 'steamapps\common')) { $libs.Add((Join-Path $s 'steamapps\common')) }
        $vdf = Join-Path $s 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($m in [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libs.Add((Join-Path ($m.Groups[1].Value -replace '\\\\', '\') 'steamapps\common'))
            }
        }
    }
    foreach ($l in $libs) { $c = Join-Path $l 'Silver'; if (Test-Path (Join-Path $c 'silver.exe')) { return $c } }
    foreach ($g in @('E:\SteamLibrary\steamapps\common\Silver', 'D:\SteamLibrary\steamapps\common\Silver')) {
        if (Test-Path (Join-Path $g 'silver.exe')) { return $g }
    }
    return ''
}

$script:logBuf = New-Object System.Text.StringBuilder
function Log([string]$s) {
    [void]$script:logBuf.AppendLine(("{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $s))
    $txtLog.Text = $script:logBuf.ToString()
    $txtLog.SelectionStart = $txtLog.Text.Length
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-VariantWanted { if ($rbZh.Checked) { return 'zh' } else { return 'latin' } }

function Update-Status {
    $dir = $txtDir.Text.Trim()
    if (-not $dir) {
        $lblStatus.Text = '当前：请先选择游戏安装目录'
        $lblStatus.ForeColor = $C_OFF
        return
    }
    if (-not (Test-Path (Join-Path $dir 'silver.exe'))) {
        $lblStatus.Text = '当前：未找到游戏（请确认目录里有 silver.exe）'
        $lblStatus.ForeColor = $C_OFF
        return
    }
    $man = Join-Path (Join-Path $dir $BakName) 'manifest.json'
    if (-not (Test-Path -LiteralPath $man)) {
        $lblStatus.Text = '当前：未安装汉化补丁'
        $lblStatus.ForeColor = $C_OFF
        return
    }
    $v = 'latin'
    try { $v = (Get-Content -LiteralPath $man -Raw -Encoding UTF8 | ConvertFrom-Json).variant } catch { }
    if (-not $v) { $v = 'latin' }
    $vn = if ($v -eq 'zh') { '人名中文版' } else { '人名英文版' }
    $bad = 0
    try {
        $out = & powershell @PSARGS -File $Inst status -GameDir $dir 2>&1
        $bad = ($out | Where-Object { $_ -match '不一致|缺失|已被改动' }).Count
    } catch { }
    if ($bad -gt 0) {
        $lblStatus.Text = "当前：已安装（$vn），但有 $bad 处与安装时不一致"
        $lblStatus.ForeColor = $C_WARN
    } else {
        $lblStatus.Text = "当前：已安装（$vn），文件一致"
        $lblStatus.ForeColor = $C_OK
    }
}

function Run-Action([string]$action) {
    if (-not (Test-Path $Inst)) { Log "找不到 install.ps1：$Inst"; return }
    $dir = $txtDir.Text.Trim()
    if (-not $dir) { Log '请先选择游戏目录。'; return }
    if (-not (Test-Path (Join-Path $dir 'silver.exe'))) { Log "该目录里没有 silver.exe：$dir"; return }
    [System.IO.File]::WriteAllText($GameTxt, $dir, (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText($VarTxt, (Get-VariantWanted), (New-Object System.Text.UTF8Encoding($false)))

    if ($action -eq 'install') {
        $man = Join-Path (Join-Path $dir $BakName) 'manifest.json'
        if (Test-Path -LiteralPath $man) {
            $q = '检测到本补丁【已安装】。' + [char]10 + [char]10 + '是否先「恢复原版」再重新安装？'
            $r = [System.Windows.Forms.MessageBox]::Show($q, '提示', 'YesNo', 'Question')
            if ($r -eq 'Yes') {
                Log '检测到已安装：先执行「恢复原版」...'
                $o2 = & powershell @PSARGS -File $Inst uninstall -GameDir $dir 2>&1
                foreach ($l in $o2) { Log ([string]$l) }
            } else {
                Log '已取消：请先点「恢复原版」，再点「安装补丁」。'
                return
            }
        }
    }

    $vn = if ((Get-VariantWanted) -eq 'zh') { '人名中文版' } else { '人名英文版' }
    Log "开始：$action（$vn）"
    $bar.Style = 'Marquee'; $bar.MarqueeAnimationSpeed = 30
    $f.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $btnA.Enabled = $btnB.Enabled = $btnC.Enabled = $false
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $out = & powershell @PSARGS -File $Inst $action -GameDir $dir -Variant (Get-VariantWanted) 2>&1
        foreach ($l in $out) { Log ([string]$l) }
        Log "完成：$action"
    } catch { Log ("出错：" + $_.Exception.Message) }
    $bar.Style = 'Blocks'
    $f.Cursor = [System.Windows.Forms.Cursors]::Default
    $btnA.Enabled = $btnB.Enabled = $btnC.Enabled = $true
    Update-Status
    Log '----------'
}

# ---------------------------------------------------------------- 界面
$f = New-Object System.Windows.Forms.Form
$f.Text = '《银色幻想》简体中文汉化补丁'
$f.ClientSize = New-Object System.Drawing.Size(700, 700)
$f.StartPosition = 'CenterScreen'
$f.BackColor = $C_BG
$f.FormBorderStyle = 'FixedSingle'
$f.MaximizeBox = $false
$f.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$head = New-Object System.Windows.Forms.Panel
$head.Location = New-Object System.Drawing.Point(0, 0)
$head.Size = New-Object System.Drawing.Size(700, 78)
$head.BackColor = $C_HEAD
$f.Controls.Add($head)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = '银 色 幻 想'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 21, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = $C_HEADTXT
$lblTitle.Location = New-Object System.Drawing.Point(24, 8)
$lblTitle.AutoSize = $true
$head.Controls.Add($lblTitle)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = '简体中文汉化补丁　·　Steam 版'
$lblSub.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 10)
$lblSub.ForeColor = [System.Drawing.Color]::FromArgb(206, 186, 152)
$lblSub.Location = New-Object System.Drawing.Point(28, 50)
$lblSub.AutoSize = $true
$head.Controls.Add($lblSub)

$lblVer = New-Object System.Windows.Forms.Label
$lblVer.Text = 'v6.3.0'
$lblVer.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 11, [System.Drawing.FontStyle]::Bold)
$lblVer.ForeColor = [System.Drawing.Color]::FromArgb(206, 186, 152)
$lblVer.TextAlign = 'MiddleRight'
$lblVer.Location = New-Object System.Drawing.Point(596, 26)
$lblVer.Size = New-Object System.Drawing.Size(84, 26)
$head.Controls.Add($lblVer)

$card1 = New-Object System.Windows.Forms.Panel
$card1.Location = New-Object System.Drawing.Point(20, 94)
$card1.Size = New-Object System.Drawing.Size(660, 78)
$card1.BackColor = $C_CARD
$f.Controls.Add($card1)

$lblDir = New-Object System.Windows.Forms.Label
$lblDir.Text = '游戏安装目录（包含 silver.exe 的文件夹）'
$lblDir.ForeColor = $C_TEXT
$lblDir.Location = New-Object System.Drawing.Point(14, 8)
$lblDir.AutoSize = $true
$card1.Controls.Add($lblDir)

$txtDir = New-Object System.Windows.Forms.TextBox
$txtDir.Location = New-Object System.Drawing.Point(16, 32)
$txtDir.Size = New-Object System.Drawing.Size(424, 24)
$txtDir.ForeColor = $C_TEXT
$card1.Controls.Add($txtDir)

$btnDetect = New-Object System.Windows.Forms.Button
$btnDetect.Text = '自动检测'
$btnDetect.Size = New-Object System.Drawing.Size(96, 26)
$btnDetect.Location = New-Object System.Drawing.Point(452, 31)
$btnDetect.FlatStyle = 'Flat'
$btnDetect.BackColor = $C_BTN1
$btnDetect.Add_Click({
    $g = Find-SteamGame
    if ($g) { $txtDir.Text = $g; Log "自动检测到游戏目录：$g" } else { Log '未能自动检测到游戏目录，请手动「浏览...」。' }
    Update-Status
})
$card1.Controls.Add($btnDetect)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = '浏览...'
$btnBrowse.Size = New-Object System.Drawing.Size(96, 26)
$btnBrowse.Location = New-Object System.Drawing.Point(554, 31)
$btnBrowse.FlatStyle = 'Flat'
$btnBrowse.BackColor = $C_BTN1
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '请选择包含 silver.exe 的游戏目录'
    if ($dlg.ShowDialog() -eq 'OK') { $txtDir.Text = $dlg.SelectedPath; Update-Status }
})
$card1.Controls.Add($btnBrowse)

$card2 = New-Object System.Windows.Forms.Panel
$card2.Location = New-Object System.Drawing.Point(20, 180)
$card2.Size = New-Object System.Drawing.Size(660, 88)
$card2.BackColor = $C_CARD
$f.Controls.Add($card2)

$lblV = New-Object System.Windows.Forms.Label
$lblV.Text = '文本版本'
$lblV.ForeColor = $C_TEXT
$lblV.Location = New-Object System.Drawing.Point(14, 6)
$lblV.AutoSize = $true
$card2.Controls.Add($lblV)

$rbLatin = New-Object System.Windows.Forms.RadioButton
$rbLatin.Text = '人名英文版（推荐）　头像下显示 Grandad / The Chronicler / Silver 等原版英文名'
$rbLatin.Location = New-Object System.Drawing.Point(16, 28)
$rbLatin.AutoSize = $true
$rbLatin.Checked = $true
$rbLatin.ForeColor = $C_TEXT
$card2.Controls.Add($rbLatin)

$rbZh = New-Object System.Windows.Forms.RadioButton
$rbZh.Text = '人名中文版（渲染期替换）　头像下显示 爷爷 / 编年史官 / 白银 等中文名　·　不碰资源键，剧情不受影响'
$rbZh.Location = New-Object System.Drawing.Point(16, 54)
$rbZh.AutoSize = $true
$rbZh.ForeColor = $C_TEXT
$card2.Controls.Add($rbZh)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = '当前：检测中...'
$lblStatus.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Bold)
$lblStatus.ForeColor = $C_OFF
$lblStatus.Location = New-Object System.Drawing.Point(24, 278)
$lblStatus.AutoSize = $true
$f.Controls.Add($lblStatus)

function New-Btn($text, $x, $w, $color, $action) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Size = New-Object System.Drawing.Size($w, 34)
    $b.Location = New-Object System.Drawing.Point($x, 304)
    $b.FlatStyle = 'Flat'
    $b.BackColor = $color
    $b.ForeColor = $C_TEXT
    $b.Add_Click({ Run-Action $action }.GetNewClosure())
    $f.Controls.Add($b)
    return $b
}
$btnA = New-Btn '验证文件' 20 140 $C_BTN1 'status'
$btnB = New-Btn '安装补丁' 170 140 $C_BTN2 'install'
$btnC = New-Btn '恢复原版' 320 140 $C_BTN3 'uninstall'

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Location = New-Object System.Drawing.Point(480, 310)
$bar.Size = New-Object System.Drawing.Size(200, 22)
$bar.Style = 'Blocks'
$f.Controls.Add($bar)

$lblLog = New-Object System.Windows.Forms.Label
$lblLog.Text = '操作日志'
$lblLog.ForeColor = $C_TEXT
$lblLog.Location = New-Object System.Drawing.Point(24, 350)
$lblLog.AutoSize = $true
$f.Controls.Add($lblLog)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.BackColor = $C_CARD
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
$txtLog.Location = New-Object System.Drawing.Point(20, 370)
$txtLog.Size = New-Object System.Drawing.Size(660, 248)
$f.Controls.Add($txtLog)

$lblNote = New-Object System.Windows.Forms.Label
$lblNote.Text = '安装会自动备份原始文件；「恢复原版」可完整还原。游戏请通过 Steam 启动。'
$lblNote.ForeColor = [System.Drawing.Color]::FromArgb(96, 88, 78)
$lblNote.Location = New-Object System.Drawing.Point(24, 628)
$lblNote.AutoSize = $true
$f.Controls.Add($lblNote)

$lblCredit = New-Object System.Windows.Forms.Label
$lblCredit.Text = 'fatman-24制作'
$lblCredit.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 12, [System.Drawing.FontStyle]::Bold)
$lblCredit.ForeColor = [System.Drawing.Color]::FromArgb(122, 92, 44)
$lblCredit.TextAlign = 'MiddleRight'
$lblCredit.Location = New-Object System.Drawing.Point(480, 658)
$lblCredit.Size = New-Object System.Drawing.Size(200, 28)
$f.Controls.Add($lblCredit)

# ---------------------------------------------------------------- 启动
try {
    if (Test-Path $GameTxt) { $txtDir.Text = (Get-Content $GameTxt -Raw).Trim() }
} catch { }
try {
    if (Test-Path $VarTxt) {
        $want = (Get-Content -LiteralPath $VarTxt -First 1).Trim().ToLower()
        if ($want -eq 'zh') { $rbZh.Checked = $true } else { $rbLatin.Checked = $true }
    }
} catch { }
try {
    $cur = $txtDir.Text.Trim()
    $ok = $false
    if ($cur) { $ok = Test-Path (Join-Path $cur 'silver.exe') }
    if (-not $ok) {
        $g = Find-SteamGame
        if ($g) { $txtDir.Text = $g; Log "已自动检测到游戏目录：$g" } else { Log '未自动找到游戏目录，请点「自动检测」或「浏览...」。' }
    }
} catch { Log ('自动检测出错: ' + $_.Exception.Message) }
Log '准备就绪。确认目录与文本版本后，点「安装补丁」。'

# 关键：先把窗口显示出来，再做状态自检（自检慢也不会让界面不出现）
$f.Add_Shown({
    # 先让窗口跳到最前面，避免以为没启动
    $f.TopMost = $true
    $f.Activate()
    $f.BringToFront()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 700
    $f.TopMost = $false
    try { Update-Status } catch { Log ('状态自检出错: ' + $_.Exception.Message) }
})
Write-Boot '窗口即将显示'
try {
    [void]$f.ShowDialog()
    Write-Boot '窗口已关闭'
} catch {
    Write-Boot ('异常: ' + $_.Exception.Message)
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '安装器出错')
}
