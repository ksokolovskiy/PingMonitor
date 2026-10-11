param(
    [string]$Target = '8.8.8.8',
    [int]$IntervalSeconds = 1,
    [int]$HistorySeconds = 60,
    [int]$TimeoutMs = 1000,
    [Alias('Opacity')]
    [double]$IdleOpacity = 0.0,
    [double]$HoverOpacity = 0.0
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$widgetPath = Join-Path $scriptDir 'ping-widget.ps1'

if (-not (Test-Path -LiteralPath $widgetPath)) {
    throw "Ping widget not found: $widgetPath"
}

$splat = @{
    Target          = $Target
    IntervalSeconds = $IntervalSeconds
    HistorySeconds  = $HistorySeconds
    TimeoutMs       = $TimeoutMs
}
if ($PSBoundParameters.ContainsKey('IdleOpacity')) { $splat['IdleOpacity'] = $IdleOpacity }
if ($PSBoundParameters.ContainsKey('HoverOpacity')) { $splat['HoverOpacity'] = $HoverOpacity }

& $widgetPath @splat
