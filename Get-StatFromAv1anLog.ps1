Param (
    [System.String]$filePath = (Join-Path -Path (Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\' -Directory |Sort-Object Creation-Time -Descending -Top 1).FullName -ChildPath 'log.log')
)

# Clear Host
Clear-Host

# Regular Expression Definition
[string]$regexp = '(?:.*chunk )(?<chunk>\d*).*Q=(?<Q>\d*).*VMAF=(?<VMAF>\d*.?\d*)'

# Read File Contents
[array]$logEntries = Get-Content -LiteralPath $filePath -Delimiter "`n"

# Initialize Results Table
[array]$resultsTable = @()

# Parse Log Entries
foreach ($line in $logEntries) {
    if ($line -match $regexp) {
        [Int32]$chunk = $matches.chunk
        [Int32]$Q     = $matches.Q
        [double]$VMAF = $matches.VMAF
        $resultsTable += [PSCustomObject]@{Chunk = $chunk; Q = $Q; VMAF = $VMAF}
    }
}

# Group and Sort Results
$groupedVMAF = $resultsTable | Group-Object VMAF | Select-Object Count, Name | Sort-Object Count, Name -Descending
$groupedQ = $resultsTable | Group-Object Q | Select-Object Count, Name | Sort-Object Count, Name -Descending

# Display Results
Write-Host "Group VMAF:" -ForegroundColor DarkYellow
$groupedVMAF | Select-Object -First 10 | Format-Table
Write-Host "Group Q:" -ForegroundColor DarkMagenta
$groupedQ | Select-Object -First 10 | Format-Table

# Display Summary Information
Write-Host $filePath -ForegroundColor Cyan
Write-Host ("Avg Q`t: {0}" -f [Math]::Round(($resultsTable | Measure-Object -Property Q -Average).Average, 2)) -ForegroundColor DarkCyan
Write-Host ("Min Q`t: {0}" -f [Math]::Round(($resultsTable | Measure-Object -Property Q -Minimum).Minimum, 2)) -ForegroundColor DarkCyan
Write-Host ("Max Q`t: {0}" -f [Math]::Round(($resultsTable | Measure-Object -Property Q -Maximum).Maximum, 2)) -ForegroundColor DarkCyan
Write-Host ("Average VMAF`t: {0}" -f [Math]::Round(($resultsTable | Measure-Object -Property VMAF -Average).Average, 2)) -ForegroundColor Cyan







<# DeepSeek chat

Param (
    [System.String]$filePath = (Join-Path -Path (Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\' -Directory |Sort-Object Creation-Time -Descending -Top 1).FullName -ChildPath 'log0.log')
    # [System.String]$filePath = (Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\logs\' -File | 
    #     Sort-Object CreationTime -Descending | 
    #     Select-Object -First 1).FullName
)

Clear-Host

# Configuration
$regexPattern = '(?:.*chunk )(?<chunk>\d*).*Q=(?<Q>\d*).*VMAF=(?<VMAF>\d*.?\d*)'
$highlightColors = @{
    VMAF = 'DarkYellow'
    Q = 'DarkMagenta'
    Path = 'Cyan'
    Stats = 'DarkCyan'
    VMAFAvg = 'Cyan'
}

# Process log file
$results = switch -Regex -File $filePath {
    $regexPattern {
        [PSCustomObject]@{
            Chunk = [int]$matches.chunk
            Q = [int]$matches.Q
            VMAF = [double]$matches.VMAF
        }
    }
}

# Group and analyze results
$analysis = [ordered]@{
    VMAF = $results | Group-Object VMAF | 
        Select-Object Count, Name | 
        Sort-Object Count, Name -Descending
    
    Q = $results | Group-Object Q | 
        Select-Object Count, Name | 
        Sort-Object Count, Name -Descending
    
    Stats = $results | Measure-Object -Property Q -Average -Minimum -Maximum
    VMAFAvg = ($results | Measure-Object -Property VMAF -Average).Average
}

# Display results
Write-Host "Group VMAF:" -ForegroundColor $highlightColors.VMAF
$analysis.VMAF | Select-Object -First 10 | Format-Table

Write-Host "Group Q:" -ForegroundColor $highlightColors.Q
$analysis.Q | Select-Object -First 10 | Format-Table

Write-Host $filePath -ForegroundColor $highlightColors.Path
Write-Host ("Avg Q`t: {0}" -f [Math]::Round($analysis.Stats.Average, 2)) -ForegroundColor $highlightColors.Stats
Write-Host ("Min Q`t: {0}" -f [Math]::Round($analysis.Stats.Minimum, 2)) -ForegroundColor $highlightColors.Stats
Write-Host ("Max Q`t: {0}" -f [Math]::Round($analysis.Stats.Maximum, 2)) -ForegroundColor $highlightColors.Stats
Write-Host ("Average VMAF`t: {0}" -f [Math]::Round($analysis.VMAFAvg, 2)) -ForegroundColor $highlightColors.VMAFAvg
#>




<# Human
Param (
    [System.String]$filePath = ((Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\logs\' -File) |
        Sort-Object CreationTime -Top 1 -Descending |
        Sort-Object -Top 1).FullName
)

[string]$filePath = ('
X:\Apps\_VideoEncoding\av1an\.e5b2242\log.log
').Trim()
    

Clear-Host
[string]$regexp = '(?:.*chunk )(?<chunk>\d*).*Q=(?<Q>\d*).*VMAF=(?<VMAF>\d*.?\d*)'

[array]$f = @(Get-Content -LiteralPath $filePath -Delimiter "`r`n") # | Where-Object {$_ -like '*Target Q=*' })
[array]$tbl = @(@())
#Write-Host $f -ForegroundColor Blue
foreach ($l in $f) {
    $matchResult = [regex]::Matches($l, $regexp)
    foreach ($m in ($matchResult)) { 
        [Int32]$chunk = $m.Groups.Item("chunk").Value
        [Int32]$Q = $m.Groups.Item("Q").Value
        [double]$VMAF = $m.Groups.Item("VMAF").Value
        $tbl += @([PSCustomObject]@{Chunk = $chunk; Q = $Q; VMAF = $VMAF })
    }
}


$tblVMAF = $tbl | Sort-Object Chunk | Group-Object VMAF | Select-Object Count, Name |  Sort-Object Count, Name -Descending
$tblQ = $tbl | Sort-Object Chunk | Group-Object Q    | Select-Object Count, Name |  Sort-Object Count, Name -Descending

Write-Host "Group VMAF:" -ForegroundColor DarkYellow
$tblVMAF | Select-Object -First 10 | Format-Table
Write-Host "Group Q:" -ForegroundColor DarkMagenta
$tblQ | Select-Object -First 10 | Format-Table

Write-Host $filePath -ForegroundColor Cyan
Write-Host ("Avg Q`t: {0}" -f [Math]::Round(($tbl | Measure-Object -Property Q -Average).Average, 2) ) -ForegroundColor DarkCyan
Write-Host ("Min Q`t: {0}" -f [Math]::Round(($tbl | Measure-Object -Property Q -Minimum).Minimum, 2) ) -ForegroundColor DarkCyan
Write-Host ("Max Q`t: {0}" -f [Math]::Round(($tbl | Measure-Object -Property Q -Maximum).Maximum, 2) ) -ForegroundColor DarkCyan
Write-Host ("Average VMAF`t: {0}" -f [Math]::Round(($tbl | Measure-Object -Property VMAF -Average).Average, 2) ) -ForegroundColor Cyan
#>