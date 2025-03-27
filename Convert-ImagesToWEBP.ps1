[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$SourceFolder = 'X:\temp2\xuk\',
    
    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$Quality = 80
)

# Extract archives
. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1
Extract-ZipArchives -SourceFolder 'Z:\www.pornpics.com\' -DestinationFolder 'X:\temp2\xuk\_pronpics_\' -Overwrite:$true -FolderForEachArchive:$true
Extract-ZipArchives -SourceFolder 'Z:\www.elitebabes.com\' -DestinationFolder 'X:\temp2\xuk\_elitebabes_\' -Overwrite:$true -FolderForEachArchive:$true

$PSStyle.Progress.View = 'Classic'
$startTime = Get-Date

# Check if cwebp is installed
if (-not (Get-Command cwebp -ErrorAction SilentlyContinue)) {
    throw "cwebp is not installed or not in PATH"
}

# Get supported image files
$imageFiles = Get-ChildItem -Path $SourceFolder -Include @('*.jpg', '*.jpeg', '*.png', '*.bmp') -File -Recurse

if (-not $imageFiles) {
    Write-Warning "No supported image files found in $SourceFolder"
    return
}

$im_convert = 'X:\Apps\_VideoEncoding\ImageMagick\convert.exe'
$total = $imageFiles.Count
$processed = 0
$converted = 0
$failed = 0
$skipped = 0
$doubled = 0
$webpTotalSize = 0
$fileTotalSize = 0

foreach ($file in $imageFiles) {
    $webpFile = if ($file.BaseName -notmatch '^\d{14}__.*') {
        "{0}\{1:yyyyMMddHHmmss}__{2}.webp" -f $file.Directory, $file.LastWriteTime, $file.BaseName
    }
    else {
        [System.IO.Path]::ChangeExtension($file.FullName, ".webp")
    }

    # Check if full duplicate already exists
    if ((Test-Path -LiteralPath $webpFile) -and ((Get-Item -LiteralPath $webpFile).LastWriteTime -eq $file.LastWriteTime)) {
        Write-Host "Exists  : $($webpFile)" -ForegroundColor Cyan
        Write-Host "Deleting: $($file.FullName)" -ForegroundColor DarkCyan
        Remove-Item -LiteralPath $file.FullName
        $doubled++
        continue
    }

    # Проверка подозрений на дубли
    $existingFiles = Get-ChildItem -Path $file.Directory.FullName | 
    Where-Object { ($_.BaseName -match ('^\d{14}__' + [regex]::Escape($file.BaseName) + '$')) }
    if ($existingFiles.Count -gt 0) {
        foreach ($existFile in $existingFiles) {
            #Write-Host "Skipping     : $($file.FullName)" -ForegroundColor Magenta
            Write-Host "Спорный дубль: $($existFile.FullName)" -ForegroundColor DarkMagenta
            $tmpWebpFile = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), 'webp')
            try {
                # Convert to temporary WebP
                $result = Start-Process $im_convert -ArgumentList "-quality $Quality `"$($file.FullName)`" `"$tmpWebpFile`"" `
                    -NoNewWindow -Wait -PassThru
                if ($result.ExitCode -ne 0) {
                    Write-Host "Conversion failed with exit code: $($result.ExitCode)"
                    continue
                }
                else {
                    if ($existFile.Length -eq (Get-Item -LiteralPath $tmpWebpFile).Length) {
                        Remove-Item -LiteralPath $file
                        Remove-Item -LiteralPath $tmpWebpFile
                        Write-Host "Дубль удалён: $($file.Name)" -ForegroundColor Magenta
                        continue
                    }
                }
            }
            catch {
                $failed++
                Write-Error "Failed convert $($file.Name) to tmp file $($tmpWebpFile)"
            }
            $skipped++
            continue
        }
    }
    else {
        # Display progress
        $processed++
        $elapsedTime = (Get-Date) - $startTime
        $averageTime = $elapsedTime.TotalSeconds / $processed
        $remainingFiles = $total - $processed
        $estimatedSeconds = $averageTime * $remainingFiles
        $estimatedTime = [TimeSpan]::FromSeconds($estimatedSeconds)
        $progressPercentage = [math]::Round(($converted + $failed) / $total * 100, 2)

        Write-Progress -Activity "Converting images to WEBP" `
            -Status "$($processed)/$($total), Current: $($file.Name)" `
            -PercentComplete $progressPercentage `
            -CurrentOperation $file.DirectoryName `
            -SecondsRemaining $estimatedTime.TotalSeconds

        try {
            # Convert to WebP
            $result = Start-Process $im_convert -ArgumentList "-quality $Quality `"$($file.FullName)`" `"$webpFile`"" `
                -NoNewWindow -Wait -PassThru
            if ($result.ExitCode -ne 0) {
                throw "Conversion failed with exit code: $($result.ExitCode)"
            }
        
            if (Test-Path -LiteralPath $webpFile) {
                $webpSize = (Get-Item -LiteralPath $webpFile).Length
            
                # Verify successful conversion
                if ($webpSize -gt 0 -and $webpSize -lt $file.Length) {
                (Get-Item -LiteralPath $webpFile).CreationTime = $file.CreationTime
                (Get-Item -LiteralPath $webpFile).LastWriteTime = $file.LastWriteTime
                
                    # Only remove original if conversion was successful
                    Remove-Item -LiteralPath $file.FullName -Force
                    $webpTotalSize += $webpSize
                    $fileTotalSize += $file.Length
                    $converted++
                }
                else {
                    throw "WebP file is larger than original or empty"
                }
            }
            else {
                throw "WebP file was not created"
            }
        }
        catch {
            $failed++
            Write-Error "Failed to convert $($file.Name): $_"
        
            # Cleanup failed conversion
            if (Test-Path -LiteralPath $webpFile) {
                Remove-Item -LiteralPath $webpFile -Force
            }
        }
    }
}
Write-Host "Conversion complete" -ForegroundColor Green
if ($converted -gt 0) {
    Write-Host "Successfully converted: $converted" -ForegroundColor DarkGreen
}
if ($failed -gt 0) {
    Write-Host "Failed: $failed" -ForegroundColor Red
}

# Close progress
Write-Progress -Activity "Converting images to WEBP" -Status "Complete" -PercentComplete 100 -Completed

#
Write-Host "Double deleted: $($doubled)" -ForegroundColor DarkMagenta


# Calculate and display time statistics
$endTime = Get-Date
$duration = $endTime - $startTime
$durationFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $duration.Hours, $duration.Minutes, $duration.Seconds
Write-Host "Time taken: $durationFormatted" -ForegroundColor DarkCyan

# Calculate and display size statistics
$originalSizeMB = [math]::Round($fileTotalSize / 1MB, 2)
$webpSizeMB = [math]::Round($webpTotalSize / 1MB, 2)
$savedSizeMB = [math]::Round(($fileTotalSize - $webpTotalSize) / 1MB, 2)
if ($fileTotalSize -gt 0) {
    $savedPercentage = [math]::Round((($fileTotalSize - $webpTotalSize) / $fileTotalSize) * 100, 2)
}
else {
    $savedPercentage = 0
}

Write-Host "Статистика конвертирования" -ForegroundColor DarkGreen
Write-Host "$($originalSizeMB) MB ==> $($webpSizeMB) MB.  Space saved: $savedSizeMB MB ($savedPercentage%)" -ForegroundColor DarkGreen