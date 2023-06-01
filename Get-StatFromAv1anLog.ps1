
Param (
    [System.String]$filePath = ('
        X:\Apps\_VideoEncoding\av1an\logs\[20230524_151235]_t[av1an][rav1e_vmaf-Q95].mkv.log
    ').Trim()
)
$regexp = '(?:.*chunk )(?<chunk>\d*).*Q=(?<Q>\d*).*VMAF=(?<VMAF>\d*.?\d*)'


Clear-Host
[array]$f = @(Get-Content -LiteralPath $filePath -Delimiter "`r`n") # | Where-Object {$_ -like '*Target Q=*' })
[array]$tbl = @(@())
#Write-Host $f -ForegroundColor Blue
foreach ($l in $f) {
    $matchResult = [regex]::Matches($l, $regexp)
    foreach ($m in ($matchResult)) { 
        [Int32]$chunk = $m.Groups.Item("chunk").Value
        [Int32]$Q     = $m.Groups.Item("Q").Value
        [double]$VMAF = $m.Groups.Item("VMAF").Value
        $tbl += @([PSCustomObject]@{Chunk=$chunk; Q=$Q; VMAF=$VMAF})
        # Write-Host ($chunk, $Q, $VMAF -join "`t") -ForegroundColor Blue
    }
}

#Write-Host "tbl: " -ForegroundColor DarkCyan
#Write-Host $tbl | Format-Table
# Write-Host "Count F  :`t$($f.Count)" -ForegroundColor DarkBlue
# Write-Host "Count tbl:`t$($tbl.Count)" -ForegroundColor DarkBlue
$tblVMAF = $tbl | Sort-Object Chunk | Group-Object VMAF | Select-Object Count, Name |  Sort-Object Count, Name -Descending
$tblQ    = $tbl | Sort-Object Chunk | Group-Object Q    | Select-Object Count, Name |  Sort-Object Count, Name -Descending

Write-Host "Group VMAF:" -ForegroundColor DarkYellow
$tblVMAF | Select-Object -First 10 | Format-Table
Write-Host "Group Q:" -ForegroundColor DarkMagenta
$tblQ | Select-Object -First 10 | Format-Table






#Write-host $($tblVMAF) -ForegroundColor DarkYellow | Format-Table
#Write-host $tblQ -ForegroundColor DarkMagenta | Format-List

#$tbl # | Sort-Object Count, Name -Descending

# $t=@([PSCustomObject]@{Chunk='1';Q='2';VMAF='3'})
# ,
# [PSCustomObject]@{Chunk='4';Q='5';VMAF='6'})


# $myitems =
# @([pscustomobject]@{name="Joe";age=32;info="something about him"},
# [pscustomobject]@{name="Sue";age=29;info="something about her"},
# [pscustomobject]@{name="Cat";age=12;info="something else"})