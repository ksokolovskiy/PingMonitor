param(
    [string]$Target = '8.8.8.8',
    [int]$IntervalSeconds = 1,
    [int]$TimeoutMs = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$IntervalSeconds = [Math]::Max(1, $IntervalSeconds)
$TimeoutMs = [Math]::Max(50, $TimeoutMs)

try {
    [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
}
catch {
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
        events            = (New-Object System.Collections.ArrayList)
    }
}

function Load-State {
    param([string]$Path, [pscustomobject]$Fallback)

    if (-not (Test-Path -LiteralPath $Path)) { return $Fallback }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not $raw) { return $Fallback }

        $state = New-State -TargetName $Fallback.target
        foreach ($name in @('all_sent','all_recv','all_sum','all_min','all_max','consecutiveLosses','lastPingMs','lastOk','target')) {
            if ($raw.PSObject.Properties[$name]) { $state.$name = $raw.$name }
        }

        if ($raw.events) {
            foreach ($e in @($raw.events)) {
                if ($null -eq $e.ts) { continue }
                $null = $state.events.Add([pscustomobject]@{
                    ts      = [int64]$e.ts
                    ok      = [bool]$e.ok
                    latency = To-Double $e.latency
                })
            }
        }

        $state.all_sent = [int64]$state.all_sent
        $state.all_recv = [int64]$state.all_recv
        $state.all_sum = To-Double $state.all_sum
        $state.all_min = To-Double $state.all_min
        $state.all_max = To-Double $state.all_max
        $state.consecutiveLosses = [int]$state.consecutiveLosses
        $state.lastPingMs = To-Double $state.lastPingMs
        $state.lastOk = [bool]$state.lastOk
        return $state
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

function New-Bucket {
    [pscustomobject]@{
        Sent = 0
        Recv = 0
        Lost = 0
        Loss = 0.0
        Min  = 0.0
        Avg  = 0.0
        Max  = 0.0
        Sum  = 0.0
    }
}

function Get-StatsSnapshot {
    param([pscustomobject]$State)

    $now = Get-UnixNow
    $from = @{
        '1m'    = $now - 60
        '1h'    = $now - 3600
        'Today' = Get-DayStartTs
    }

    $stats = @{
        '1m'    = New-Bucket
        '1h'    = New-Bucket
        'Today' = New-Bucket
        'All'   = Get-AllTimeStats -State $State
    }

    foreach ($e in $State.events) {
        $ts = [int64]$e.ts
        foreach ($name in @('1m','1h','Today')) {
            if ($ts -lt $from[$name]) { continue }
            $bucket = $stats[$name]
            $bucket.Sent++
            if ([bool]$e.ok) {
                $bucket.Recv++
                $lat = To-Double $e.latency
                $bucket.Sum += $lat
                if ($bucket.Min -eq 0 -or $lat -lt $bucket.Min) { $bucket.Min = $lat }
                if ($lat -gt $bucket.Max) { $bucket.Max = $lat }
            }
        }
    }

    foreach ($name in @('1m','1h','Today')) {
        $bucket = $stats[$name]
        $bucket.Lost = $bucket.Sent - $bucket.Recv
        $bucket.Loss = if ($bucket.Sent -gt 0) { 100.0 * $bucket.Lost / $bucket.Sent } else { 0.0 }
        $bucket.Avg = if ($bucket.Recv -gt 0) { $bucket.Sum / $bucket.Recv } else { 0.0 }
        $bucket.PSObject.Properties.Remove('Sum')
    }

    return $stats
}

function Add-Sample {
    param([pscustomobject]$State, [bool]$Ok, [double]$Latency)

    $ts = Get-UnixNow
    $State.all_sent++

    if ($Ok) {
        $State.all_recv++
        $State.all_sum += $Latency
        if ($State.all_min -eq 0 -or $Latency -lt $State.all_min) { $State.all_min = $Latency }
        if ($Latency -gt $State.all_max) { $State.all_max = $Latency }
        $State.consecutiveLosses = 0
        $State.lastPingMs = $Latency
        $State.lastOk = $true
    }
    else {
        $State.consecutiveLosses++
        $State.lastOk = $false
    }

    $null = $State.events.Add([pscustomobject]@{
        ts      = $ts
        ok      = $Ok
        latency = if ($Ok) { $Latency } else { 0.0 }
    })

    $cutoff = $ts - 86400
    while ($State.events.Count -gt 0 -and [int64]$State.events[0].ts -lt $cutoff) {
        $State.events.RemoveAt(0)
    }
}

function Print-Line {
    param([string]$Name, [pscustomobject]$Stats)

    Write-Host ("{0,-12} Sent: {1,6}  Received: {2,6}  Lost: {3,6} ({4,5:N1}%)  Ping min/avg/max: {5,6:N1}/{6,6:N1}/{7,6:N1} ms" -f `
        $Name, $Stats.Sent, $Stats.Recv, $Stats.Lost, ([double]$Stats.Loss), ([double]$Stats.Min), ([double]$Stats.Avg), ([double]$Stats.Max))
}

function Redraw {
    param([pscustomobject]$State, [bool]$First)

    $stats = Get-StatsSnapshot -State $State
    if (-not $First) {
        try {
            [Console]::SetCursorPosition(0, [Math]::Max(0, [Console]::CursorTop - 5))
        }
        catch {
            Write-Host ("{0}[5A" -f [char]27) -NoNewline
        }
    }

    $status = if ($State.lastOk) { ('{0:N0} ms' -f [double]$State.lastPingMs) } else { 'TIMEOUT' }
    Write-Host ("Target: {0}  Last: {1}  Updated: {2:HH:mm:ss}               " -f $State.target, $status, (Get-Date))
    Print-Line 'Last minute' $stats['1m']
    Print-Line 'Last hour' $stats['1h']
    Print-Line 'Today' $stats['Today']
    Print-Line 'All time' $stats['All']
}

$stateDir = Join-Path $env:LOCALAPPDATA 'PingMonitor'
$stateFile = Join-Path $stateDir ("ping-stats-$($Target -replace '[:\\/]', '_').json")
$state = Load-State -Path $stateFile -Fallback (New-State -TargetName $Target)
$state.target = $Target
$ping = New-Object System.Net.NetworkInformation.Ping
$saveCounter = 0
$first = $true

Write-Host ("Monitoring {0} every {1} s. Ctrl+C to stop." -f $Target, $IntervalSeconds)

try {
    while ($true) {
        $started = [DateTime]::UtcNow
        $ok = $false
        $latency = 0.0

        try {
            $reply = $ping.Send($state.target, $TimeoutMs)
            if ($reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
                $ok = $true
                $latency = [double]$reply.RoundtripTime
            }
        }
        catch {
            $ok = $false
        }

        Add-Sample -State $state -Ok $ok -Latency $latency
        $saveCounter++
        if ($saveCounter -ge 300) {
            Save-State -State $state -Path $stateFile
            $saveCounter = 0
        }

        Redraw -State $state -First $first
        $first = $false

        $elapsedMs = ([DateTime]::UtcNow - $started).TotalMilliseconds
        $sleepMs = [Math]::Max(1, ($IntervalSeconds * 1000) - [int]$elapsedMs)
        Start-Sleep -Milliseconds $sleepMs
    }
}
finally {
    Save-State -State $state -Path $stateFile
    $ping.Dispose()
}
