param(
    [string]$Target = '8.8.8.8',
    [int]$IntervalSeconds = 1,
    [int]$HistorySeconds = 60,
    [int]$TimeoutMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$IntervalSeconds = [Math]::Max(1, $IntervalSeconds)
$HistorySeconds = [Math]::Max(60, $HistorySeconds)
$TimeoutMs = [Math]::Max(50, $TimeoutMs)

$script:state = $null
$script:ping = New-Object System.Net.NetworkInformation.Ping
$script:saveCounter = 0
$script:expanded = $false
$script:lastStats = @{}
$script:draggingControl = $false
$script:dragStartMouse = [System.Drawing.Point]::Empty
$script:dragStartForm = [System.Drawing.Point]::Empty

$lossThresholds = [pscustomobject]@{
    GoodMax = 0.5
    WarnMax = 2.0
    BadMax  = 5.0
}

$colors = [pscustomobject]@{
    Back   = [System.Drawing.Color]::FromArgb(24, 26, 31)
    Panel  = [System.Drawing.Color]::FromArgb(34, 37, 44)
    Panel2 = [System.Drawing.Color]::FromArgb(42, 45, 53)
    Text   = [System.Drawing.Color]::FromArgb(236, 239, 244)
    Muted  = [System.Drawing.Color]::FromArgb(164, 171, 181)
    Green  = [System.Drawing.Color]::FromArgb(73, 190, 113)
    Yellow = [System.Drawing.Color]::FromArgb(205, 202, 75)
    Orange = [System.Drawing.Color]::FromArgb(235, 149, 58)
    Red    = [System.Drawing.Color]::FromArgb(229, 77, 77)
}

function Get-UnixNow {
    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    [int64]([DateTime]::UtcNow - $epoch).TotalSeconds
}

function Get-DayStartTs {
    $today = Get-Date
    $dayStart = New-Object DateTime($today.Year, $today.Month, $today.Day, 0, 0, 0, [DateTimeKind]::Local)
    $epoch = New-Object DateTime 1970, 1, 1, 0, 0, 0, ([DateTimeKind]::Utc)
    [int64]($dayStart.ToUniversalTime() - $epoch).TotalSeconds
}

function To-Double {
    param([object]$Value)
    if ($null -eq $Value) { return 0.0 }
    [double]$Value
}

function New-State {
    param([string]$TargetName)
    [pscustomobject]@{
        target            = $TargetName
        all_sent          = 0L
        all_recv          = 0L
        all_sum           = 0.0
        all_min           = 0.0
        all_max           = 0.0
        consecutiveLosses = 0
        lastPingMs        = 0.0
        lastOk            = $false
        events            = @()
    }
}

function Load-State {
    param([string]$Path, [pscustomobject]$Fallback)

    if (-not (Test-Path -LiteralPath $Path)) { return $Fallback }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $raw) { return $Fallback }

        $loaded = New-State -TargetName $Fallback.target
        foreach ($name in @('all_sent','all_recv','all_sum','all_min','all_max','consecutiveLosses','lastPingMs','lastOk','target')) {
            if ($raw.PSObject.Properties[$name]) { $loaded.$name = $raw.$name }
        }

        if ($raw.events) {
            $items = New-Object System.Collections.ArrayList
            foreach ($e in @($raw.events)) {
                if ($null -eq $e.ts) { continue }
                $null = $items.Add([pscustomobject]@{
                    ts      = [int64]$e.ts
                    ok      = [bool]$e.ok
                    latency = To-Double $e.latency
                })
            }
            $loaded.events = @($items)
        }

        $loaded.all_sent = [int64]$loaded.all_sent
        $loaded.all_recv = [int64]$loaded.all_recv
        $loaded.all_sum = To-Double $loaded.all_sum
        $loaded.all_min = To-Double $loaded.all_min
        $loaded.all_max = To-Double $loaded.all_max
        $loaded.consecutiveLosses = [int]$loaded.consecutiveLosses
        $loaded.lastPingMs = To-Double $loaded.lastPingMs
        $loaded.lastOk = [bool]$loaded.lastOk
        return $loaded
    }
    catch {
        return $Fallback
    }
}

function Save-State {
    param([pscustomobject]$State, [string]$Path)

    try {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        $State | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
    }
}

function Get-RangeStats {
    param([int64]$FromTs, [array]$Events)

    $sent = 0
    $recv = 0
    $sum = 0.0
    $min = 0.0
    $max = 0.0

    foreach ($e in @($Events)) {
        if ([int64]$e.ts -lt $FromTs) { continue }
        $sent++
        if ([bool]$e.ok) {
            $recv++
            $lat = To-Double $e.latency
            $sum += $lat
            if ($min -eq 0 -or $lat -lt $min) { $min = $lat }
            if ($lat -gt $max) { $max = $lat }
        }
    }

    $lost = $sent - $recv
    [pscustomobject]@{
        Sent = $sent
        Recv = $recv
        Lost = $lost
        Loss = if ($sent -gt 0) { 100.0 * $lost / $sent } else { 0.0 }
        Min  = $min
        Avg  = if ($recv -gt 0) { $sum / $recv } else { 0.0 }
        Max  = $max
    }
}

function Get-AllTimeStats {
    param([pscustomobject]$State)

    $lost = $State.all_sent - $State.all_recv
    [pscustomobject]@{
        Sent = $State.all_sent
        Recv = $State.all_recv
        Lost = $lost
        Loss = if ($State.all_sent -gt 0) { 100.0 * $lost / $State.all_sent } else { 0.0 }
        Min  = $State.all_min
        Avg  = if ($State.all_recv -gt 0) { $State.all_sum / $State.all_recv } else { 0.0 }
        Max  = $State.all_max
    }
}

function Get-LossColor {
    param([double]$Loss)

    if ($Loss -gt $lossThresholds.BadMax) { return $colors.Red }
    if ($Loss -gt $lossThresholds.WarnMax) { return $colors.Orange }
    if ($Loss -gt $lossThresholds.GoodMax) { return $colors.Yellow }
    return $colors.Green
}

function Get-StatusColor {
    param([pscustomobject]$Stats1m)

    if ($script:state.consecutiveLosses -ge 4) { return $colors.Red }
    if ($script:state.consecutiveLosses -ge 2) { return $colors.Orange }
    return Get-LossColor -Loss ([double]$Stats1m.Loss)
}

function Get-StatusText {
    param([pscustomobject]$Stats1m)

    if ($script:state.consecutiveLosses -ge 4) { return 'OFFLINE' }
    if ($script:state.consecutiveLosses -ge 2 -or [double]$Stats1m.Loss -gt $lossThresholds.GoodMax) { return 'DEGRADED' }
    return 'ONLINE'
}

function Format-Latency {
    if ($script:state.all_sent -le 0) { return '--' }
    if (-not $script:state.lastOk) { return 'TIMEOUT' }
    return ('{0:N0} ms' -f [double]$script:state.lastPingMs)
}

function Format-Tooltip {
    param([string]$Title, [pscustomobject]$Stats)

    return ("{0}`r`n`r`nSent: {1}`r`nReceived: {2}`r`nLost: {3}`r`nLoss: {4:N2}%`r`n`r`nPing:`r`nMin: {5:N0} ms`r`nAvg: {6:N0} ms`r`nMax: {7:N0} ms" -f `
        $Title, $Stats.Sent, $Stats.Recv, $Stats.Lost, [double]$Stats.Loss, [double]$Stats.Min, [double]$Stats.Avg, [double]$Stats.Max)
}

function New-Label {
    param(
        [string]$Text,
        [System.Drawing.Font]$Font,
        [System.Drawing.ContentAlignment]$Align = [System.Drawing.ContentAlignment]::MiddleLeft
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Font = $Font
    $label.ForeColor = $colors.Text
    $label.TextAlign = $Align
    $label.Dock = [System.Windows.Forms.DockStyle]::Fill
    $label.AutoEllipsis = $true
    return $label
}

function New-LossBlock {
    param([string]$Key)

    $label = New-Label -Text ($Key + '  --') -Font (New-Object System.Drawing.Font('Consolas', 10, [System.Drawing.FontStyle]::Bold)) -Align ([System.Drawing.ContentAlignment]::MiddleCenter)
    $label.BackColor = $colors.Panel2
    $label.Margin = New-Object System.Windows.Forms.Padding(3, 0, 3, 0)
    $label.Padding = New-Object System.Windows.Forms.Padding(6, 0, 6, 0)
    return $label
}

function Add-DragMove {
    param([System.Windows.Forms.Control]$Control, [System.Windows.Forms.Form]$Form)

    $Control.Add_MouseDown({
        param($sender, $e)
        if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
        $script:draggingControl = $true
        $script:dragStartMouse = [System.Windows.Forms.Cursor]::Position
        $script:dragStartForm = $Form.Location
    })

    $Control.Add_MouseMove({
        if (-not $script:draggingControl) { return }
        $now = [System.Windows.Forms.Cursor]::Position
        $dx = $now.X - $script:dragStartMouse.X
        $dy = $now.Y - $script:dragStartMouse.Y
        $Form.Location = New-Object System.Drawing.Point(($script:dragStartForm.X + $dx), ($script:dragStartForm.Y + $dy))
    })

    $Control.Add_MouseUp({ $script:draggingControl = $false })
}

$stateDir = Join-Path $env:LOCALAPPDATA 'PingMonitor'
$stateFile = Join-Path $stateDir ("ping-stats-$($Target -replace '[:\\/]', '_').json")
$debugFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'ping-widget.last.json'
$script:state = Load-State -Path $stateFile -Fallback (New-State -TargetName $Target)
$script:state.target = $Target

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Ping Widget'
$form.Size = New-Object System.Drawing.Size(470, 112)
$form.MinimumSize = New-Object System.Drawing.Size(420, 108)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.BackColor = $colors.Back
$form.ForeColor = $colors.Text
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::SizableToolWindow

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem('Exit')
$exitItem.Add_Click({ $form.Close() })
$null = $menu.Items.Add($exitItem)
$form.ContextMenuStrip = $menu

$tooltip = New-Object System.Windows.Forms.ToolTip
$tooltip.InitialDelay = 200
$tooltip.ReshowDelay = 100
$tooltip.AutoPopDelay = 5000
$tooltip.ShowAlways = $true

$root = New-Object System.Windows.Forms.TableLayoutPanel
$root.Dock = [System.Windows.Forms.DockStyle]::Fill
$root.BackColor = $colors.Back
$root.Padding = New-Object System.Windows.Forms.Padding(8, 7, 8, 7)
$root.ColumnCount = 1
$root.RowCount = 3
$null = $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 36)))
$null = $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 32)))
$null = $root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$form.Controls.Add($root)

$top = New-Object System.Windows.Forms.TableLayoutPanel
$top.Dock = [System.Windows.Forms.DockStyle]::Fill
$top.ColumnCount = 6
$top.RowCount = 1
$top.BackColor = $colors.Back
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 18)))
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 34)))
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 26)))
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 22)))
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 18)))
$null = $top.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 26)))

$dotLabel = New-Label -Text 'o' -Font (New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)) -Align ([System.Drawing.ContentAlignment]::MiddleCenter)
$hostLabel = New-Label -Text $Target -Font (New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold))
$statusLabel = New-Label -Text 'STARTING' -Font (New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)) -Align ([System.Drawing.ContentAlignment]::MiddleCenter)
$latencyLabel = New-Label -Text '--' -Font (New-Object System.Drawing.Font('Consolas', 11, [System.Drawing.FontStyle]::Bold)) -Align ([System.Drawing.ContentAlignment]::MiddleCenter)
$timeLabel = New-Label -Text (Get-Date -Format 'HH:mm:ss') -Font (New-Object System.Drawing.Font('Consolas', 9)) -Align ([System.Drawing.ContentAlignment]::MiddleRight)
$toggleButton = New-Object System.Windows.Forms.Button
$toggleButton.Text = 'v'
$toggleButton.Dock = [System.Windows.Forms.DockStyle]::Fill
$toggleButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$toggleButton.FlatAppearance.BorderSize = 0
$toggleButton.BackColor = $colors.Panel
$toggleButton.ForeColor = $colors.Muted
$toggleButton.Font = New-Object System.Drawing.Font('Consolas', 9, [System.Drawing.FontStyle]::Bold)
$toggleButton.Margin = New-Object System.Windows.Forms.Padding(3, 4, 0, 4)

$null = $top.Controls.Add($dotLabel, 0, 0)
$null = $top.Controls.Add($hostLabel, 1, 0)
$null = $top.Controls.Add($statusLabel, 2, 0)
$null = $top.Controls.Add($latencyLabel, 3, 0)
$null = $top.Controls.Add($timeLabel, 4, 0)
$null = $top.Controls.Add($toggleButton, 5, 0)
$null = $root.Controls.Add($top, 0, 0)

$periods = New-Object System.Windows.Forms.TableLayoutPanel
$periods.Dock = [System.Windows.Forms.DockStyle]::Fill
$periods.ColumnCount = 4
$periods.RowCount = 1
$periods.BackColor = $colors.Back
0..3 | ForEach-Object {
    $null = $periods.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 25)))
}

$periodLabels = @{
    '1m'    = New-LossBlock -Key '1m'
    '1h'    = New-LossBlock -Key '1h'
    'Today' = New-LossBlock -Key 'Today'
    'All'   = New-LossBlock -Key 'All'
}
$null = $periods.Controls.Add($periodLabels['1m'], 0, 0)
$null = $periods.Controls.Add($periodLabels['1h'], 1, 0)
$null = $periods.Controls.Add($periodLabels['Today'], 2, 0)
$null = $periods.Controls.Add($periodLabels['All'], 3, 0)
$null = $root.Controls.Add($periods, 0, 1)

$details = New-Object System.Windows.Forms.TableLayoutPanel
$details.Dock = [System.Windows.Forms.DockStyle]::Fill
$details.Visible = $false
$details.BackColor = $colors.Back
$details.ColumnCount = 5
$details.RowCount = 5
$details.Margin = New-Object System.Windows.Forms.Padding(0, 8, 0, 0)
$null = $details.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 26)))
1..4 | ForEach-Object {
    $null = $details.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 18.5)))
}
0..4 | ForEach-Object {
    $null = $details.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 24)))
}

$detailCells = @{}
$headers = @('', 'LOSS', 'SENT', 'LOST', 'AVG')
for ($c = 0; $c -lt $headers.Count; $c++) {
    $lbl = New-Label -Text $headers[$c] -Font (New-Object System.Drawing.Font('Consolas', 8, [System.Drawing.FontStyle]::Bold)) -Align ([System.Drawing.ContentAlignment]::MiddleRight)
    $lbl.ForeColor = $colors.Muted
    $null = $details.Controls.Add($lbl, $c, 0)
}

$detailFields = @('LOSS','SENT','LOST','AVG')
$rows = @('1m','1h','Today','All')
for ($r = 0; $r -lt $rows.Count; $r++) {
    $name = $rows[$r]
    $rowIndex = $r + 1
    $title = New-Label -Text $name -Font (New-Object System.Drawing.Font('Consolas', 8.5, [System.Drawing.FontStyle]::Bold))
    $null = $details.Controls.Add($title, 0, $rowIndex)
    foreach ($field in $detailFields) {
        $lbl = New-Label -Text '--' -Font (New-Object System.Drawing.Font('Consolas', 8.5)) -Align ([System.Drawing.ContentAlignment]::MiddleRight)
        $detailCells["$name.$field"] = $lbl
        $col = [Array]::IndexOf($detailFields, $field) + 1
        $null = $details.Controls.Add($lbl, $col, $rowIndex)
    }
}
$null = $root.Controls.Add($details, 0, 2)

function Set-Expanded {
    param([bool]$Value)

    $script:expanded = $Value
    $details.Visible = $Value
    if ($Value) {
        $form.Size = New-Object System.Drawing.Size([Math]::Max($form.Width, 500), 220)
        $toggleButton.Text = '^'
    }
    else {
        $form.Size = New-Object System.Drawing.Size([Math]::Max($form.Width, 470), 112)
        $toggleButton.Text = 'v'
    }
}

function Update-Ui {
    $now = Get-UnixNow
    $script:lastStats = @{
        '1m'    = Get-RangeStats -FromTs ($now - 60) -Events $script:state.events
        '1h'    = Get-RangeStats -FromTs ($now - 3600) -Events $script:state.events
        'Today' = Get-RangeStats -FromTs (Get-DayStartTs) -Events $script:state.events
        'All'   = Get-AllTimeStats -State $script:state
    }

    $stats1m = $script:lastStats['1m']
    $statusColor = Get-StatusColor -Stats1m $stats1m
    $statusText = Get-StatusText -Stats1m $stats1m

    $dotLabel.ForeColor = $statusColor
    $hostLabel.Text = $script:state.target
    $statusLabel.Text = $statusText
    $statusLabel.ForeColor = $statusColor
    $latencyLabel.Text = Format-Latency
    $latencyLabel.ForeColor = if ($script:state.lastOk) { $colors.Text } else { $colors.Red }
    $timeLabel.Text = Get-Date -Format 'HH:mm:ss'

    foreach ($key in @('1m','1h','Today','All')) {
        $stats = $script:lastStats[$key]
        $lossColor = Get-LossColor -Loss ([double]$stats.Loss)
        $label = $periodLabels[$key]
        $label.Text = ('{0}  {1:N1}%' -f $key, [double]$stats.Loss)
        $label.ForeColor = $colors.Text
        $label.BackColor = [System.Drawing.Color]::FromArgb(44, $lossColor.R, $lossColor.G, $lossColor.B)
        $tooltip.SetToolTip($label, (Format-Tooltip -Title $key -Stats $stats))

        $detailCells["$key.LOSS"].Text = ('{0:N1}%' -f [double]$stats.Loss)
        $detailCells["$key.LOSS"].ForeColor = $lossColor
        $detailCells["$key.SENT"].Text = [string]$stats.Sent
        $detailCells["$key.LOST"].Text = [string]$stats.Lost
        $detailCells["$key.AVG"].Text = if ($stats.Recv -gt 0) { ('{0:N0}' -f [double]$stats.Avg) } else { '--' }
    }

    $tooltip.SetToolTip($top, ("{0}`r`nSent: {1}`r`nReceived: {2}`r`nLost: {3}" -f $script:state.target, $script:state.all_sent, $script:state.all_recv, ($script:state.all_sent - $script:state.all_recv)))

    try {
        [pscustomobject]@{
            updatedAt = (Get-Date).ToString('s')
            target    = $script:state.target
            allSent   = [int64]$script:state.all_sent
            allRecv   = [int64]$script:state.all_recv
            lastOk    = [bool]$script:state.lastOk
            lastPingMs = [double]$script:state.lastPingMs
            samples1m = [int]$script:lastStats['1m'].Sent
            recv1m    = [int]$script:lastStats['1m'].Recv
            samples1h = [int]$script:lastStats['1h'].Sent
            samplesDay = [int]$script:lastStats['Today'].Sent
            loss1m    = [double]$script:lastStats['1m'].Loss
            lossAll   = [double]$script:lastStats['All'].Loss
        } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath $debugFile -Encoding UTF8
    }
    catch {
    }
}

function Add-Sample {
    param([bool]$Ok, [double]$Latency)

    $ts = Get-UnixNow
    $evt = [pscustomobject]@{
        ts      = $ts
        ok      = $Ok
        latency = if ($Ok) { $Latency } else { 0.0 }
    }

    $script:state.all_sent++
    if ($Ok) {
        $script:state.all_recv++
        $script:state.all_sum += $Latency
        if ($script:state.all_min -eq 0 -or $Latency -lt $script:state.all_min) { $script:state.all_min = $Latency }
        if ($Latency -gt $script:state.all_max) { $script:state.all_max = $Latency }
        $script:state.consecutiveLosses = 0
        $script:state.lastPingMs = $Latency
        $script:state.lastOk = $true
    }
    else {
        $script:state.consecutiveLosses++
        $script:state.lastOk = $false
    }

    $script:state.events = @($script:state.events + $evt | Where-Object { [int64]$_.ts -ge ($ts - 86400) })
}

function Run-PingCycle {
    $ok = $false
    $latency = 0.0

    try {
        $reply = $script:ping.Send($script:state.target, $TimeoutMs)
        if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $ok = $true
            $latency = [double]$reply.RoundtripTime
        }
    }
    catch {
        $ok = $false
    }

    Add-Sample -Ok $ok -Latency $latency
    $script:saveCounter++
    if ($script:saveCounter -ge 5) {
        Save-State -State $script:state -Path $stateFile
        $script:saveCounter = 0
    }
    Update-Ui
}

$toggleButton.Add_Click({ Set-Expanded -Value (-not $script:expanded) })
$form.Add_DoubleClick({ Set-Expanded -Value (-not $script:expanded) })
$root.Add_DoubleClick({ Set-Expanded -Value (-not $script:expanded) })
foreach ($control in @($top, $periods, $hostLabel, $statusLabel, $latencyLabel, $timeLabel)) {
    Add-DragMove -Control $control -Form $form
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = [int]($IntervalSeconds * 1000)
$timer.Add_Tick({ Run-PingCycle })

$form.Add_Shown({
    Update-Ui
    Run-PingCycle
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
    $timer.Dispose()
    Save-State -State $script:state -Path $stateFile
    if ($null -ne $script:ping) { $script:ping.Dispose() }
})

Update-Ui
$null = $form.ShowDialog()
Save-State -State $script:state -Path $stateFile
