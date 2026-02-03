<#
.SYNOPSIS
    Модуль для ремукса видеофайлов в MKV контейнер
#>

function Convert-ToMKVUniversal {
    <#
    .SYNOPSIS
        Конвертирует любой видеофайл в MKV контейнер с правильной обработкой всех потоков
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
        [string]$InputFile,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputFile,
        
        [switch]$KeepTempFiles
    )
    
    $tempDir = $null
    $tempFiles = [System.Collections.Generic.List[string]]::new()
    
    try {
        $inputItem = Get-Item -LiteralPath $InputFile
        $inputExtension = [System.IO.Path]::GetExtension($InputFile).ToLower()
        
        Write-Log "Ремукс $($inputItem.Name) в MKV..." -Severity Information -Category 'Remux'
        
        # ============================================
        # ПЕРВЫЙ ЭТАП: ПРОВЕРКА СУЩЕСТВУЮЩЕГО ФАЙЛА
        # ============================================
        
        if (Test-Path -LiteralPath $OutputFile -PathType Leaf) {
            Write-Log "Выходной файл уже существует, проверяем его содержимое..." -Severity Information -Category 'Remux'
            
            # Получаем информацию об исходном файле
            $originalInfo = Get-VideoFileInfo -InputFile $InputFile
            
            # Проверяем существующий файл
            $existingInfo = & $global:VideoTools.MkvMerge -J $OutputFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                $existingJson = $existingInfo | ConvertFrom-Json
                
                $originalVideoCount = $originalInfo.Streams.Video.Count
                $originalAudioCount = $originalInfo.Streams.Audio.Count
                $originalSubsCount = $originalInfo.Streams.Subtitles.Count
                
                $existingVideoCount = ($existingJson.tracks | Where-Object { $_.type -eq 'video' }).Count
                $existingAudioCount = ($existingJson.tracks | Where-Object { $_.type -eq 'audio' }).Count
                $existingSubsCount = ($existingJson.tracks | Where-Object { $_.type -eq 'subtitles' }).Count
                
                Write-Log "Сравнение дорожек:" -Severity Information -Category 'Remux'
                Write-Log "  Видео: оригинал=$originalVideoCount, существующий=$existingVideoCount" -Severity Information -Category 'Remux'
                Write-Log "  Аудио: оригинал=$originalAudioCount, существующий=$existingAudioCount" -Severity Information -Category 'Remux'
                Write-Log "  Субтитры: оригинал=$originalSubsCount, существующий=$existingSubsCount" -Severity Information -Category 'Remux'
                
                if ($originalVideoCount -eq $existingVideoCount -and 
                    $originalAudioCount -eq $existingAudioCount -and 
                    $originalSubsCount -eq $existingSubsCount) {
                    
                    Write-Log "Существующий файл прошел проверку! Используем его." -Severity Success -Category 'Remux'
                    
                    # Проверяем качество файла через Test-RemuxResult
                    $result = Test-RemuxResult -OutputFile $OutputFile -OriginalInfo $originalInfo
                    
                    if ($result -eq $OutputFile) {
                        Write-Log "Файл $([System.IO.Path]::GetFileName($OutputFile)) уже обработан и готов к использованию" `
                            -Severity Success -Category 'Remux'
                        return $OutputFile
                    } else {
                        Write-Log "Файл не прошел проверку качества, выполняем ремукс заново" -Severity Warning -Category 'Remux'
                    }
                } else {
                    Write-Log "Количество дорожек не совпадает, выполняем ремукс заново" -Severity Warning -Category 'Remux'
                }
            } else {
                Write-Log "Существующий файл поврежден или не читается, выполняем ремукс" -Severity Warning -Category 'Remux'
            }
        }
        
        # ============================================
        # ВТОРОЙ ЭТАП: ВЫПОЛНЕНИЕ РЕМУКСА
        # ============================================
        
        # Создаем временную директорию
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "mkv_remux_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempFiles.Add($tempDir)
        
        # 1. Анализируем исходный файл
        $fileInfo = Get-VideoFileInfo -InputFile $InputFile
        
        # 2. Обрабатываем вложения/обложки
        $attachments = Get-Attachments -InputFile $InputFile -FileInfo $fileInfo -TempDir $tempDir
        if ($attachments.Files.Count -gt 0) { $tempFiles.AddRange($attachments.Files) }
        
        # 3. Извлекаем главы (если есть)
        $chaptersFile = Get-Chapters -InputFile $InputFile -InputExtension $inputExtension -TempDir $tempDir
        if ($chaptersFile) { $tempFiles.Add($chaptersFile) }
        
        # 4. Ремуксим основное содержимое
        Invoke-MainContentRemux -InputFile $InputFile -OutputFile $OutputFile -FileInfo $fileInfo
        
        # 5. Добавляем вложения через mkvpropedit
        if ($attachments.Files.Count -gt 0 -and (Test-Path -LiteralPath $OutputFile)) {
            Add-AttachmentsToMKV -OutputFile $OutputFile -Attachments $attachments
        }
        
        # 6. Добавляем главы (если есть)
        if ($chaptersFile -and (Test-Path -LiteralPath $chaptersFile)) {
            Add-ChaptersToMKV -OutputFile $OutputFile -ChaptersFile $chaptersFile
        }
        
        # 7. Проверяем результат
        return Test-RemuxResult -OutputFile $OutputFile -OriginalInfo $fileInfo
        
    }
    catch {
        Write-Log "Ошибка при ремуксе в MKV: $_" -Severity Error -Category 'Remux'
        throw
    }
    finally {
        # Удаляем временные файлы
        if (-not $KeepTempFiles) {
            Remove-TempFiles -TempFiles $tempFiles
        } else {
            Write-Log "Временные файлы сохранены в: $tempDir" -Severity Information -Category 'Remux'
        }
    }
}

function Get-VideoFileInfo {
    [CmdletBinding()]
    param([string]$InputFile)
    
    $ffprobeArgs = @(
        "-v", "error",
        "-show_entries", "stream=index,codec_type,codec_name,disposition,tags:format_tags",
        "-of", "json",
        $InputFile
    )
    
    $fileInfo = & $global:VideoTools.FFprobe @ffprobeArgs | ConvertFrom-Json
    
    # Группируем потоки по типам
    $streamsByType = @{
        Video     = @($fileInfo.streams | Where-Object { $_.codec_type -eq 'video' })
        Audio     = @($fileInfo.streams | Where-Object { $_.codec_type -eq 'audio' })
        Subtitles = @($fileInfo.streams | Where-Object { $_.codec_type -eq 'subtitle' })
        Attachments = @($fileInfo.streams | Where-Object { 
            $_.codec_type -eq 'attachment' -or 
            ($_.disposition -and $_.disposition.attached_pic -eq 1)
        })
    }
    
    Write-Log "Обнаружено: $($streamsByType.Video.Count) видео, $($streamsByType.Audio.Count) аудио, $($streamsByType.Subtitles.Count) субтитров, $($streamsByType.Attachments.Count) вложений" -Severity Information -Category 'Remux'
    
    return @{
        Streams = $streamsByType
        FormatTags = $fileInfo.format.tags
        RawInfo = $fileInfo
    }
}

function Get-Attachments {
    [CmdletBinding()]
    param(
        [string]$InputFile,
        [hashtable]$FileInfo,
        [string]$TempDir
    )
    
    $attachments = @()
    $attachmentFiles = @()
    
    foreach ($stream in $FileInfo.Streams.Attachments) {
        try {
            $streamIndex = $stream.index
            $mimeType = $stream.tags.mimetype
            $filename = $stream.tags.filename
            
            # Определяем, является ли это обложкой
            $isCover = $false
            if ($filename -match 'cover|poster|folder' -or 
                ($mimeType -like 'image/*' -and $stream.disposition.attached_pic -eq 1)) {
                $isCover = $true
                Write-Log "Обнаружена обложка: $filename ($mimeType)" -Severity Information -Category 'Remux'
            }
            
            # Извлекаем вложение
            $attachmentFile = Join-Path $tempDir "attachment_$streamIndex.dat"
            $ffmpegExtractArgs = @(
                "-y", "-hide_banner", "-loglevel", "error",
                "-i", $InputFile,
                "-map", "0:$streamIndex",
                "-c", "copy",
                $attachmentFile
            )
            
            & $global:VideoTools.FFmpeg @ffmpegExtractArgs
            
            if (Test-Path -LiteralPath $attachmentFile) {
                $attachmentInfo = @{
                    Path = $attachmentFile
                    Index = $streamIndex
                    Filename = $filename
                    MimeType = $mimeType
                    IsCover = $isCover
                }
                
                $attachments += $attachmentInfo
                $attachmentFiles += $attachmentFile
            }
        }
        catch {
            Write-Log "Ошибка извлечения вложения $($stream.index): $_" -Severity Warning -Category 'Remux'
        }
    }
    
    return @{
        Info = $attachments
        Files = $attachmentFiles
    }
}

function Get-Chapters {
    [CmdletBinding()]
    param(
        [string]$InputFile,
        [string]$InputExtension,
        [string]$TempDir
    )
    
    # Извлекаем главы только для форматов, которые их поддерживают
    if ($inputExtension -notin @('.mp4', '.m4v', '.mov', '.mkv', '.mpls')) {
        return $null
    }
    
    try {
        $chaptersFile = Join-Path $tempDir "chapters.txt"
        
        if ($inputExtension -eq '.mkv') {
            # Для MKV используем mkvextract
            $mkvextractArgs = @($InputFile, "chapters", $chaptersFile)
            & $global:VideoTools.MkvExtract @mkvextractArgs 2>&1 | Out-Null
        } else {
            # Для MP4/MOV используем ffmpeg
            $ffmpegArgs = @(
                "-y", "-hide_banner", "-loglevel", "error",
                "-i", $InputFile,
                "-f", "ffmetadata",
                $chaptersFile
            )
            
            & $global:VideoTools.FFmpeg @ffmpegArgs
        }
        
        if (Test-Path -LiteralPath $chaptersFile -and (Get-Item $chaptersFile).Length -gt 0) {
            Write-Log "Главы извлечены" -Severity Information -Category 'Remux'
            
            # Конвертируем в XML для mkvmerge если нужно
            if ($inputExtension -ne '.mkv') {
                $chaptersXml = Join-Path $tempDir "chapters.xml"
                Convert-MP4ChaptersToXML -InputFile $chaptersFile -OutputFile $chaptersXml
                if (Test-Path -LiteralPath $chaptersXml) {
                    return $chaptersXml
                }
            }
            
            return $chaptersFile
        }
    }
    catch {
        Write-Log "Ошибка извлечения глав: $_" -Severity Warning -Category 'Remux'
    }
    
    return $null
}

function Invoke-MainContentRemux {
    [CmdletBinding()]
    param(
        [string]$InputFile,
        [string]$OutputFile,
        [hashtable]$FileInfo
    )
    
    Write-Log "Ремукс видео, аудио и субтитров..." -Severity Information -Category 'Remux'
    
    # Формируем аргументы для ffmpeg
    $ffmpegArgs = @(
        "-y", "-hide_banner", "-loglevel", "warning",
        "-i", $InputFile
    )
    
    # Исключаем вложения из основного ремукса
    $mapArgs = @()
    $totalStreams = $FileInfo.RawInfo.streams.Count
    
    for ($i = 0; $i -lt $totalStreams; $i++) {
        $stream = $FileInfo.RawInfo.streams[$i]
        if ($stream.codec_type -ne 'attachment' -and 
            -not ($stream.disposition -and $stream.disposition.attached_pic -eq 1)) {
            $mapArgs += "-map", "0:$i"
        }
    }
    
    $ffmpegArgs += $mapArgs
    $ffmpegArgs += @(
        "-c", "copy",
        "-max_interleave_delta", "0",
        "-avoid_negative_ts", "make_zero",
        "-fflags", "+genpts",
        "-strict", "-2",
        $OutputFile
    )
    
    # Специфичные параметры для MP4
    $inputExtension = [System.IO.Path]::GetExtension($InputFile).ToLower()
    if ($inputExtension -in @('.mp4', '.mov', '.m4v')) {
        $ffmpegArgs = $ffmpegArgs[0..($ffmpegArgs.Count-2)] + @("-movflags", "+faststart", $OutputFile)
    }
    
    Write-Log "Выполнение: ffmpeg $($ffmpegArgs -join ' ')" -Severity Debug -Category 'Remux'
    
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    & $global:VideoTools.FFmpeg @ffmpegArgs 2>&1 | Out-Null
    $timer.Stop()
    
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка ремукса (код $LASTEXITCODE)"
    }
    
    Write-Log "Основной ремукс завершен за $($timer.Elapsed.ToString('mm\:ss'))" -Severity Information -Category 'Remux'
}

function Add-AttachmentsToMKV {
    [CmdletBinding()]
    param(
        [string]$OutputFile,
        [hashtable]$Attachments
    )
    
    Write-Log "Добавление вложений через mkvpropedit..." -Severity Information -Category 'Remux'
    
    foreach ($attachment in $Attachments.Info) {
        try {
            $mkvpropeditArgs = @($OutputFile, "--add-attachment", $attachment.Path)
            
            if ($attachment.Filename) {
                $mkvpropeditArgs += "--attachment-name", $attachment.Filename
            }
            
            if ($attachment.MimeType) {
                $mkvpropeditArgs += "--attachment-mime-type", $attachment.MimeType
            } elseif ($attachment.Path -match '\.(jpg|jpeg)$') {
                $mkvpropeditArgs += "--attachment-mime-type", "image/jpeg"
            } elseif ($attachment.Path -match '\.png$') {
                $mkvpropeditArgs += "--attachment-mime-type", "image/png"
            } elseif ($attachment.Path -match '\.webp$') {
                $mkvpropeditArgs += "--attachment-mime-type", "image/webp"
            }
            
            if ($attachment.IsCover) {
                $mkvpropeditArgs += "--attachment-description", "Cover"
            }
            
            & $global:VideoTools.MkvPropedit @mkvpropeditArgs
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "Вложение добавлено: $($attachment.Filename)" -Severity Success -Category 'Remux'
            }
        }
        catch {
            Write-Log "Ошибка добавления вложения $($attachment.Filename): $_" -Severity Warning -Category 'Remux'
        }
    }
}

function Add-ChaptersToMKV {
    [CmdletBinding()]
    param(
        [string]$OutputFile,
        [string]$ChaptersFile
    )
    
    try {
        Write-Log "Добавление глав..." -Severity Information -Category 'Remux'
        
        $tempOutput = "${OutputFile}_with_chapters.mkv"
        $mkvmergeArgs = @(
            "--ui-language", "en",
            "--output", $tempOutput,
            "--chapters", $ChaptersFile,
            $OutputFile
        )
        
        & $global:VideoTools.MkvMerge @mkvmergeArgs
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path $tempOutput)) {
            Move-Item -LiteralPath $tempOutput -Destination $OutputFile -Force
            Write-Log "Главы успешно добавлены" -Severity Success -Category 'Remux'
        }
    }
    catch {
        Write-Log "Предупреждение: не удалось добавить главы" -Severity Warning -Category 'Remux'
    }
}

function Test-RemuxResult {
    [CmdletBinding()]
    param(
        [string]$OutputFile,
        [hashtable]$OriginalInfo
    )
    
    if (-not (Test-Path -LiteralPath $OutputFile -PathType Leaf)) {
        throw "Выходной файл не создан"
    }
    
    $outputSize = (Get-Item -LiteralPath $OutputFile).Length / 1MB
    Write-Log ("Ремукс завершен - Размер: {0:N2} MB" -f $outputSize) -Severity Success -Category 'Remux'
    
    # Проверяем содержимое полученного файла
    try {
        $checkArgs = @("-J", $OutputFile)
        $mkvInfo = & $global:VideoTools.MkvMerge @checkArgs | ConvertFrom-Json
        
        $finalVideo = ($mkvInfo.tracks | Where-Object { $_.type -eq 'video' }).Count
        $finalAudio = ($mkvInfo.tracks | Where-Object { $_.type -eq 'audio' }).Count
        $finalSubs = ($mkvInfo.tracks | Where-Object { $_.type -eq 'subtitles' }).Count
        $finalAttach = if ($mkvInfo.attachments) { $mkvInfo.attachments.Count } else { 0 }
        
        Write-Log "Результат: $finalVideo видео, $finalAudio аудио, $finalSubs субтитров, $finalAttach вложений" `
            -Severity Information -Category 'Remux'
        
        # Сравниваем с оригиналом
        if ($finalVideo -ne $OriginalInfo.Streams.Video.Count) {
            Write-Log "Предупреждение: количество видеодорожек изменилось" -Severity Warning -Category 'Remux'
        }
        
        if ($finalAudio -ne $OriginalInfo.Streams.Audio.Count) {
            Write-Log "Предупреждение: количество аудиодорожек изменилось" -Severity Warning -Category 'Remux'
        }
        
        return $OutputFile
    }
    catch {
        Write-Log "Не удалось проверить результат ремукса: $_" -Severity Warning -Category 'Remux'
        return $OutputFile
    }
}

function Remove-TempFiles {
    [CmdletBinding()]
    param([System.Collections.Generic.List[string]]$TempFiles)
    
    foreach ($file in $TempFiles) {
        try {
            if (Test-Path -LiteralPath $file) {
                Remove-Item -LiteralPath $file -Force -Recurse -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Log "Не удалось удалить временный файл $file" -Severity Warning -Category 'Remux'
        }
    }
}

function Get-SupportedVideoFormats {
    <#
    .SYNOPSIS
        Возвращает список поддерживаемых форматов видео
    #>
    return @(
        '.mkv', '.mp4', '.avi', '.mov', '.mpg', '.mpeg', 
        '.wmv', '.flv', '.m4v', '.ts', '.m2ts', '.vob',
        '.ogv', '.webm', '.rmvb', '.divx', '.xvid', '.mpls'
    )
}

function Test-NeedRemux {
    <#
    .SYNOPSIS
        Проверяет, нужен ли ремукс файла в MKV
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath)
    
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    
    # Всегда ремуксим не-MKV файлы
    if ($extension -ne '.mkv') {
        return $true
    }
    
    # Для MKV проверяем возможные проблемы
    try {
        # Пытаемся прочитать файл через mkvmerge
        $testArgs = @("-J", $FilePath)
        & $global:VideoTools.MkvMerge @testArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            # Файл корректный, ремукс не нужен
            return $false
        } else {
            # Файл поврежден или имеет проблемы, нужен ремукс
            Write-Log "MKV файл имеет проблемы, требуется ремукс" -Severity Warning -Category 'Remux'
            return $true
        }
    }
    catch {
        # Если не удалось проверить, предполагаем что нужен ремукс
        return $true
    }
}

Export-ModuleMember -Function Convert-ToMKVUniversal, Get-SupportedVideoFormats, Test-NeedRemux