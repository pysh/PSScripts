
Param (
    [System.String]$filePath = ((Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\logs\' -File) |
        Sort-Object CreationTime -Top 1 -Descending |
        Sort-Object -Top 1).FullName
)

# [System.String]$filePath = ('
# y:\.temp\Zolotoe.Dno\vpy_dgdecnv\test\Zolotoe.dno.s01e01_test [svt_av1_vmaf93].mkv.log
# ').Trim()
    

# Clear-Host
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
        # Write-Host ($chunk, $Q, $VMAF -join "`t") -ForegroundColor Blue
    }
}

#Write-Host "tbl: " -ForegroundColor DarkCyan
#Write-Host $tbl | Format-Table
# Write-Host "Count F  :`t$($f.Count)" -ForegroundColor DarkBlue
# Write-Host "Count tbl:`t$($tbl.Count)" -ForegroundColor DarkBlue
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