# MKVProcessor.psm1 - PowerShell module for MKV file processing
# Requires PowerShell 7.5+ and MKVToolNix

using namespace System.IO

class MKVFileInfo {
    [string]$Path
    [string]$Name
    [string]$Directory
    [string]$BaseName
    [long]$SizeMB
    [string]$GuestName
    
    MKVFileInfo([string]$FilePath) {
        $this.Path = $FilePath
        $this.Name = [Path]::GetFileName($FilePath)
        $this.Directory = [Path]::GetDirectoryName($FilePath)
        $this.BaseName = [Path]::GetFileNameWithoutExtension($FilePath)
        $this.SizeMB = [math]::Round((Get-Item -LiteralPath $FilePath).Length / 1MB, 2)
        $this.GuestName = $this.ExtractGuestName()
    }
    
    [string] ExtractGuestName() {
        if ($this.Name -match '.*\s-\s(?<guest>.*?)\s\[.*') {
            return $Matches.guest.Trim()
        }
        return $null
    }
}

function Get-MKVGuestName {
    <#
    .SYNOPSIS
        Extracts guest name from MKV filename pattern
    #>
    param([string]$FileName)
    
    if ($FileName -match '.*\s-\s(?<guest>.*?)\s\[.*') {
        return $Matches.guest.Trim()
    }
    return $null
}

function New-MKVDescription {
    <#
    .SYNOPSIS
        Generates standardized description for MKV files
    #>
    param([string]$GuestName)
    
    $baseDescription = @" 
«Я себя знаю!» — это псевдоинтеллектуальная псевдовикторина, в которой Азамат Мусагалиев попытается найти и задать селебам вопросы о них, на которые они не смогут ответить. Зачем? Да специально, чтобы за каждый неправильный ответ услышать от звезды отвратительный факт из её биографии.
"@

    if ($GuestName) {
        return $baseDescription + "`nГость: $GuestName"
    }
    return $baseDescription
}

function Clear-TagText {
    <#
    .SYNOPSIS
        Cleans tag text by removing Erid paragraphs and VK Video references
    #>
    param([string]$Text)
    
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }
    
    # Split into paragraphs (empty line as separator)
    $paragraphs = $Text -split "`r`n`r`n|`n`n|`r`r"
    
    # Filter paragraphs
    $filteredParagraphs = @()
    
    foreach ($paragraph in $paragraphs) {
        $paragraph = $paragraph.Trim()
        
        if (-not [string]::IsNullOrWhiteSpace($paragraph)) {
            # Remove paragraphs ending with Erid:.*
            if ($paragraph -match "Erid:\s*\S+\s*$") {
                Write-Verbose "Удален абзац с Erid: $($paragraph -replace '\s+', ' ' | Select-String -Pattern 'Erid:\s*\S+' | ForEach-Object { $_.Matches.Value })"
                continue
            }
            
            # Remove "Эксклюзивно в VK Видео." string
            $paragraph = $paragraph -replace "Эксклюзивно в VK Видео\.", ""
            
            $filteredParagraphs += $paragraph
        }
    }
    
    # Rejoin into text
    return ($filteredParagraphs -join "`r`n`r`n").Trim()
}

function Export-CleanedMKVTags {
    <#
    .SYNOPSIS
        Exports and cleans MKV tags, keeping only specified ones
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$InputFile,
        
        [Parameter(Mandatory)]
        [string]$TagsFile,
        
        [string[]]$AllowedTags = @("COMMENT", "ARTIST", "DATE", "DESCRIPTION", "SYNOPSIS", "PURL"),
        
        [switch]$UseStandardDescription
    )
    
    process {
        try {
            $mkvInfo = [MKVFileInfo]::new($InputFile)
            $tempTagsFile = [Path]::ChangeExtension($InputFile, "tags_tmp.xml")
            
            Write-Verbose "Экспорт тегов из: $InputFile"
            $extractResult = & mkvextract $InputFile tags $tempTagsFile 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Ошибка экспорта тегов: $($extractResult -join ' ')"
                return $false
            }
            
            if (-not (Test-Path -LiteralPath $tempTagsFile) -or (Get-Item -LiteralPath $tempTagsFile).Length -eq 0) {
                Write-Warning "Файл тегов пуст или не создан"
                return $false
            }
            
            # Read and process XML
            [xml]$tagsXml = Get-Content -LiteralPath $tempTagsFile -Encoding UTF8
            
            # Generate standard description if requested
            $standardDescription = if ($UseStandardDescription) {
                New-MKVDescription -GuestName $mkvInfo.GuestName
            }
            
            # Process tags
            $simpleTags = $tagsXml.SelectNodes("//Simple")
            $modifiedCount = 0
            
            foreach ($tag in $simpleTags) {
                if ($AllowedTags -contains $tag.Name) {
                    if ($UseStandardDescription -and @("DESCRIPTION", "SYNOPSIS") -contains $tag.Name) {
                        $tag.String = $standardDescription
                        $modifiedCount++
                        Write-Verbose "Установлено стандартное описание для тега: $($tag.Name)"
                    }
                    elseif ($tag.String -and -not [string]::IsNullOrWhiteSpace($tag.String)) {
                        $cleanedText = Clear-TagText -Text $tag.String
                        if ($cleanedText -ne $tag.String) {
                            $tag.String = $cleanedText
                            $modifiedCount++
                            Write-Verbose "Очищен тег: $($tag.Name)"
                        }
                    }
                }
                else {
                    $tag.ParentNode.RemoveChild($tag) | Out-Null
                }
            }
            
            # Remove empty tags
            $emptyTags = $tagsXml.SelectNodes("//Tag[count(Simple)=0]")
            foreach ($emptyTag in $emptyTags) {
                $emptyTag.ParentNode.RemoveChild($emptyTag) | Out-Null
            }
            
            # Save cleaned XML
            $tagsXml.Save($TagsFile)
            Write-Verbose "Сохранено очищенных тегов в: $TagsFile"
            
            return $true
        }
        catch {
            Write-Error "Ошибка обработки тегов: $($_.Exception.Message)"
            return $false
        }
        finally {
            if (Test-Path -LiteralPath $tempTagsFile) {
                Remove-Item -LiteralPath $tempTagsFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

function Invoke-MKVRemux {
    <#
    .SYNOPSIS
        Remuxes MKV file with optional frame rate change and tag cleaning
    .EXAMPLE
        Invoke-MKVRemux -InputFile "video.mkv" -FrameRate 25 -CleanTags
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'FilePath')]
        [string]$InputFile,
        
        [string]$OutputFile,
        
        [ValidateRange(1, 60)]
        [int]$FrameRate = 25,
        
        [switch]$CleanTags,
        
        [switch]$UseStandardDescription,
        
        [string[]]$AllowedTags = @("COMMENT", "ARTIST", "DATE", "DESCRIPTION", "SYNOPSIS", "PURL"),
        
        [switch]$Force
    )
    
    begin {
        $script:AllowedTags = $AllowedTags
    }
    
    process {
        try {
            # Validate input file
            if (-not (Test-Path -LiteralPath $InputFile)) {
                Write-Error "Файл не найден: $InputFile"
                return
            }
            
            if ([Path]::GetExtension($InputFile) -ne '.mkv') {
                Write-Error "Файл должен иметь расширение .mkv: $InputFile"
                return
            }
            
            $mkvInfo = [MKVFileInfo]::new($InputFile)
            
            # Generate output filename
            if ([string]::IsNullOrEmpty($OutputFile)) {
                $OutputFile = Join-Path $mkvInfo.Directory "${$mkvInfo.BaseName}_${FrameRate}fps.mkv"
            }
            
            # Confirm overwrite
            if (Test-Path -LiteralPath $OutputFile) {
                if (-not $Force -and -not $PSCmdlet.ShouldContinue(
                    "Выходной файл уже существует: $OutputFile", 
                    "Подтверждение перезаписи")) {
                    Write-Host "Операция отменена" -ForegroundColor Yellow
                    return
                }
            }
            
            if ($PSCmdlet.ShouldProcess($InputFile, "Remux to $OutputFile")) {
                Write-Host "Обработка файла: $($mkvInfo.Name)" -ForegroundColor Cyan
                Write-Host "Выходной файл: $(Split-Path $OutputFile -Leaf)" -ForegroundColor Cyan
                Write-Host "Частота кадров: ${FrameRate}fps" -ForegroundColor Cyan
                
                $mkvmergeArgs = @(
                    "--output", $OutputFile
                    "--default-duration", "0:${FrameRate}fps"
                    "--fix-bitstream-timing-information", "0:1"
                )
                
                if ($CleanTags) {
                    Write-Host "Режим: Очистка тегов" -ForegroundColor Green
                    
                    $tagsFile = [Path]::ChangeExtension($InputFile, "tags.xml")
                    $tagsExported = Export-CleanedMKVTags `
                        -InputFile $InputFile `
                        -TagsFile $tagsFile `
                        -AllowedTags $AllowedTags `
                        -UseStandardDescription:$UseStandardDescription `
                        -Verbose:$($VerbosePreference -eq 'Continue')
                    
                    if ($tagsExported) {
                        $mkvmergeArgs += @(
                            "--no-track-tags"
                            "--no-global-tags" 
                            "--global-tags", $tagsFile
                            "--output-charset", "utf-8"
                        )
                    }
                    else {
                        Write-Warning "Продолжаем без обработки тегов"
                    }
                }
                else {
                    Write-Host "Режим: Простая установка FPS" -ForegroundColor Gray
                }
                
                $mkvmergeArgs += $InputFile
                
                Write-Verbose "Выполняется: mkvmerge $($mkvmergeArgs -join ' ')"
                & mkvmerge @mkvmergeArgs
                
                if ($LASTEXITCODE -eq 0) {
                    $outputInfo = [MKVFileInfo]::new($OutputFile)
                    
                    Write-Host "`nОбработка завершена успешно!" -ForegroundColor Green
                    Write-Host "Размер исходного файла: $($mkvInfo.SizeMB) MB" -ForegroundColor Gray
                    Write-Host "Размер выходного файла: $($outputInfo.SizeMB) MB" -ForegroundColor Gray
                    
                    if ($CleanTags) {
                        Write-Host "`nПроверка тегов:" -ForegroundColor Cyan
                        & mkvextract $OutputFile tags 2>&1 | 
                            Select-String -Pattern ($AllowedTags -join '|') -Context 1 |
                            ForEach-Object { Write-Host $_.Line -ForegroundColor White }
                    }
                }
                else {
                    Write-Error "Ошибка mkvmerge. Код выхода: $LASTEXITCODE"
                }
            }
        }
        catch {
            Write-Error "Ошибка обработки: $($_.Exception.Message)"
        }
    }
}

function Start-BatchMKVRemux {
    <#
    .SYNOPSIS
        Batch processes multiple MKV files
    .EXAMPLE
        Get-ChildItem "C:\Videos\*.mkv" | Start-BatchMKVRemux -FrameRate 25 -CleanTags
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('FullName', 'FilePath')]
        [string[]]$InputFile,
        
        [string]$OutputDirectory,
        
        [ValidateRange(1, 60)]
        [int]$FrameRate = 25,
        
        [switch]$CleanTags,
        
        [switch]$UseStandardDescription,
        
        [switch]$Force,
        
        [int]$ThrottleLimit = 2
    )
    
    process {
        $jobs = @()
        
        foreach ($file in $InputFile) {
            $outputFile = if ($OutputDirectory) {
                $name = [Path]::GetFileNameWithoutExtension($file) + "_${FrameRate}fps.mkv"
                Join-Path $OutputDirectory $name
            }
            else {
                $null
            }
            
            $jobScript = {
                param($FilePath, $OutFile, $FPS, $Clean, $StandardDesc, $ForceFlag)
                Import-Module MKVProcessor -Force
                Invoke-MKVRemux -InputFile $FilePath -OutputFile $OutFile -FrameRate $FPS -CleanTags:$Clean -UseStandardDescription:$StandardDesc -Force:$ForceFlag
            }
            
            $job = Start-ThreadJob -ScriptBlock $jobScript -ArgumentList @(
                $file, $outputFile, $FrameRate, $CleanTags, $UseStandardDescription, $Force
            ) -ThrottleLimit $ThrottleLimit
            
            $jobs += $job
            Write-Host "Запущена обработка: $(Split-Path $file -Leaf)" -ForegroundColor Yellow
        }
        
        # Wait for all jobs and receive results
        $jobs | Wait-Job | Receive-Job -Wait
        
        # Cleanup jobs
        $jobs | Remove-Job -Force
    }
}

# Export module members
Export-ModuleMember -Function @(
    'Invoke-MKVRemux'
    'Start-BatchMKVRemux' 
    'Get-MKVGuestName'
    'New-MKVDescription'
    'Clear-TagText'
    'Export-CleanedMKVTags'
)