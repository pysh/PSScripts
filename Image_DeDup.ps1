# Image DeDup
Clear-Host
$path = 'X:\temp2\xuk\'
$filterList = @('.jpg', '.jpeg', '.webp')
$extraFilter = "*-*_*__*"

$files = Get-ChildItem -LiteralPath $path -File -Recurse |
Where-Object {
            ($_.Extension -iin $filterList) -and
            ($_.BaseName -like $extraFilter)
}
Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen
$d=0
foreach ($f in $files) {
    # $f24001800 = Join-Path $f.Directory -ChildPath ($f.BaseName.Replace('_2400_', '_1800_') + $f.Extension)
    if ($f.BaseName -like '*-*_2400__*') {
        $regExpString = '(?<g1>.*)_(?<g2>\d*)__(?<g3>\d*)(?<gext>.*)'
        $rgx = ($f.BaseName -match $regExpString)
        if ($Matches.Count -gt 0) {
            #Write-Host $f.FullName -ForegroundColor DarkCyan
            #$f24001800 = Join-Path $f.Directory -ChildPath ("{0}_{1}__{2}{3}" -f $Matches.g1, '1800', $Matches.g3, $f.Extension)
            #Write-Host $f24001800 -ForegroundColor Cyan
            
            $regExpString2 = (".*\\{0}_{1}__{2}\{3}" -f $Matches.g1, '1800', '.*', $f.Extension)
            #$regExpString
            # Clear-Variable $rgx
            $rgx = ($files.FullName -match $regExpString2)
            if ($rgx.Count -gt 0) {
                foreach ($df in $rgx) {
                    if (Test-Path $df -PathType Leaf) {
                        $dfi = Get-Item $df
                        $fileToDelete = Join-Path $f.Directory -ChildPath ($dfi.Name)
                        if (Test-Path $fileToDelete -PathType Leaf) {
                            Write-Host ("Deleting $($dfi.Name) = $($f.Name)") -ForegroundColor DarkMagenta
                            Remove-Item $fileToDelete
                            #Move-Item $fileToDelete -Destination ("{0}.bak" -f $fileToDelete)
                            $d += 1
                        }
                    }
                }
            }
            
            # if (Test-Path -Path $f24001800 -PathType Leaf) {
            # }
        }
    }
}
Write-Host ("Удалено файлов: {0}" -f $d)



# # Image DeDup
# Clear-Host
# $path = 'X:\temp2\xuk\'
# $filterList = @('.jpg', '.jpeg')
# $extraFilter = "*-*_*__*"

# $files = Get-ChildItem -LiteralPath $path -File -Recurse |
# Where-Object {
#     ($_.Extension -iin $filterList) -and
#     ($_.BaseName -like $extraFilter)
# }
# Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen
# $deletedFileCount = 0

# foreach ($file in $files) {
#     if ($file.BaseName -like '*-*_2400__*') {
#         $regExpString = '(?<g1>.*)_(?<g2>\d*)__(?<g3>\d*)(?<gext>.*)'
#         if ($file.BaseName -match $regExpString) {
#             $regExpString2 = ("{0}_{1}__{2}{3}" -f $Matches.g1, '1800', '.*', $file.Extension)
#             $matchingFiles = Get-ChildItem -LiteralPath $path -File -Recurse |
#             Where-Object {
#                 $_.FullName -match $regExpString2
#             }
#             foreach ($matchingFile in $matchingFiles) {
#                 if (Test-Path $matchingFile.FullName -PathType Leaf) {
#                     try {
#                         Write-Host $matchingFile.FullName -ForegroundColor DarkMagenta
#                         Remove-Item $matchingFile.FullName -ErrorAction Stop
#                         $deletedFileCount += 1
#                     } catch {
#                         Write-Host ("Error deleting file: {0}" -f $_.Exception.Message) -ForegroundColor Red
#                     }
#                 }
#             }
#         }
#     }
# }
# Write-Host ("Удалено файлов: {0}" -f $deletedFileCount) -ForegroundColor DarkGreen