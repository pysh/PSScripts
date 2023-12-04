Clear-Host
#$ErrorActionPreference = 'SilentlyContinue'
[bool]$isTest = $true
$PSStyle.Progress.View = 'Classic'
$files = (Get-ChildItem -LiteralPath 'V:\' -Recurse -File)
[Int32]$fc = $files.Count
[Int32]$c = 0
$dtFrom = Get-Date
foreach ($f in $files) {
    $c += 1
    $prc = ($c / $fc * 100)
    #Write-Host "= = = = = = ="
    #Write-Host $fc, $c, $prc
    $dtCurrent = Get-Date
    $dtSec = $dtCurrent - $dtFrom
    [Int32]$intSeconds = ($fc * $dtSec.TotalSeconds / $c) - $dtSec.TotalSeconds
    Write-Progress -Activity 'Scanning...' -Status $f.Name -PercentComplete $prc -CurrentOperation $f.Directory -SecondsRemaining $intSeconds


    # $c  => $dtSec
    # $fc => xxx


    #Start-Sleep -Milliseconds 200
    #Write-Host $f.FullName
    try {
        if (((Get-Item -LiteralPath $f.FullName -Stream *) | Where-Object { $_.Stream -eq '.gltth' }).Count -gt 1) {
            try {
                Write-Host ('{0}  Deleteting stream.' -f $f) DarkGreen
                $a = $f.Attributes 
                # if ($f.Attributes -eq 'ReadOnly') { $f.Attributes -= 'ReadOnly' }
                # if ($f.Attributes -eq 'Hidden') { $f.Attributes -= 'Hidden' }
                # Unblock-File -LiteralPath $f.FullName
                if (-not $isTest) {
                    Remove-Item -LiteralPath $f.FullName -stream '.gltth'
                    Remove-Item -LiteralPath $f.FullName -stream 'Shareaza.GUID'
                    Remove-Item -LiteralPath $f.FullName -stream 'Zone.Identifier'
                }
                Write-Host 'OK' -ForegroundColor Green
            }
            catch {
                Write-Host ('{0}  Delete stream error.' -f $f) DarkYellow
                # Start-Sleep 5
            }
            finally {
                $f.Attributes = $a
            }
        }
        else {
            # Write-Host 'NO STREAMS FOUND' -ForegroundColor DarkBlue
        }
    }
    catch {
        Write-Host ('{0}  Get stream error.' -f $f) -ForegroundColor DarkMagenta
        # Write-Host $_ -ForegroundColor Magenta
        # Start-Sleep 5
    }
}
Write-Progress -Activity 'Scanning...' -Completed
$ErrorActionPreference = 'Continue'
Write-Host ($(Get-Date) - $dtFrom)