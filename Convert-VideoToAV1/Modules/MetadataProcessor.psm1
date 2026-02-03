<#
.SYNOPSIS
    Модуль для обработки метаданных мультимедиа (универсальный для MKV)
#>

using namespace System.Xml
using namespace System.Text

# ============================================
# ОСНОВНЫЕ ФУНКЦИИ (публичные)
# ============================================

function Invoke-ProcessMetaData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)

    try {
        Write-Log "Начало обработки метаданных" -Severity Information -Category 'Metadata'
        
        # Инициализация директории метаданных
        $metadataDir = Initialize-MetadataDirectory -Job $Job
        
        # Поиск и копирование обложки
        Find-CoverFile -Job $Job -SourceDir ([IO.Path]::GetDirectoryName($Job.OriginalPath))
        
        # Получение информации о файле через mkvmerge
        $fileInfo = Get-MKVFileInfo -VideoPath $Job.VideoPath
        
        # Извлечение различных типов метаданных
        Get-Attachments -FileInfo $fileInfo -Job $Job -MetadataDir $metadataDir
        Get-Subtitles -FileInfo $fileInfo -Job $Job -MetadataDir $metadataDir
        Get-Chapters -Job $Job -MetadataDir $metadataDir
        
        # Обработка NFO файла
        Get-NfoFile -Job $Job
        
        # Добавление директории метаданных в список временных файлов
        $Job.TempFiles.Add($metadataDir)
        
        Write-Log "Обработка метаданных завершена" -Severity Success -Category 'Metadata'
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке метаданных: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

function Complete-MediaFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)

    try {
        Write-Log "Начало создания итогового файла" -Severity Information -Category 'Muxing'
        
        # Формирование заголовка файла
        $fileTitle = Get-FileTitle -Job $Job
        
        # Построение базовых аргументов для mkvmerge
        $mkvArgs = Build-BaseMkvMergeArgs -OutputFile $Job.FinalOutput -VideoFile $Job.VideoOutput -Title $fileTitle
        
        # Добавление аудиодорожек
        $mkvArgs = Add-AudioTracksToArgs -MkvArgs $mkvArgs -AudioTracks $Job.AudioOutputs
        
        # Добавление субтитров
        $mkvArgs = Add-SubtitlesToArgs -MkvArgs $mkvArgs -Subtitles $Job.Metadata.Subtitles
        
        # Добавление глав
        $mkvArgs = Add-ChaptersToArgs -MkvArgs $mkvArgs -Job $Job
        
        # Добавление тегов
        $mkvArgs = Add-TagsToArgs -MkvArgs $mkvArgs -TagsFile $Job.NfoTags
        
        Write-Log "Выполняемая команда: mkvmerge $($mkvArgs -join ' ')" -Severity Debug -Category 'Muxing'
        
        # Выполнение mkvmerge
        Invoke-MkvMerge -Arguments $mkvArgs
        
        # Добавление обложки
        Add-CoverToMKV -Job $Job
        
        # Добавление тега EncoderParams
        Add-EncoderParamsTag -Job $Job
        
        Write-Log "Файл успешно создан: $($Job.FinalOutput)" -Severity Success -Category 'Muxing'
    }
    catch {
        Write-Log "Ошибка при создании итогового файла: $_" -Severity Error -Category 'Muxing'
        throw
    }
}

function ConvertFrom-NfoToXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NfoFile,
        [Parameter(Mandatory)][string]$OutputFile
    )

    try {
        [xml]$nfoContent = Get-Content -LiteralPath $NfoFile -ErrorAction Stop
        $episode = $nfoContent.episodedetails
        
        # Создание XML документа
        $fields = ConvertFrom-NfoToTagsXml -Episode $episode -OutputFile $OutputFile
        return $fields
    }
    catch {
        Write-Log "Ошибка при конвертации NFO в XML: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

# ============================================
# ФУНКЦИИ ИЗВЛЕЧЕНИЯ МЕТАДАННЫХ (внутренние)
# ============================================

function Initialize-MetadataDirectory {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    $metadataDir = Join-Path -Path $Job.WorkingDir -ChildPath "meta"
    New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
    
    $Job.Metadata = @{ 
        TempDir = $metadataDir
        Attachments = [System.Collections.Generic.List[object]]::new()
        Subtitles = [System.Collections.Generic.List[object]]::new()
    }
    
    return $metadataDir
}

function Get-MKVFileInfo {
    [CmdletBinding()]
    param([string]$VideoPath)
    
    $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $jsonInfo = & $global:VideoTools.MkvMerge -J $VideoPath | ConvertFrom-Json
    [Console]::OutputEncoding = $originalEncoding
    
    return $jsonInfo
}

function Get-Attachments {
    [CmdletBinding()]
    param(
        [object]$FileInfo,
        [hashtable]$Job,
        [string]$MetadataDir
    )
    
    if (-not $FileInfo.attachments) { 
        Write-Log "Вложения не обнаружены" -Severity Verbose -Category 'Metadata'
        return 
    }
    
    Write-Log "Извлечение вложений ($($FileInfo.attachments.Count) шт.)" -Severity Information -Category 'Metadata'
    
    foreach ($attachment in $FileInfo.attachments) {
        try {
            # Пропускаем обложки
            if ($attachment.file_name -match '^(cover|folder)\.(jpg|png|webp)$') {
                Write-Log "Пропуск вложения-обложки: $($attachment.file_name)" -Severity Verbose -Category 'Metadata'
                continue
            }
            
            $safeName = [IO.Path]::GetFileName($attachment.file_name) -replace '[^\w\.-]', '_'
            $outputFile = Join-Path -Path $MetadataDir -ChildPath "attach_$($attachment.id)_$safeName"
            
            & $global:VideoTools.MkvExtract $Job.VideoPath attachments "$($attachment.id):$outputFile" *>$null
            
            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                $attachmentInfo = @{
                    Path        = $outputFile
                    Name        = $attachment.file_name
                    Mime        = $attachment.content_type
                    Description = $attachment.description
                    Id          = $attachment.id
                }
                
                $Job.Metadata.Attachments.Add($attachmentInfo)
                Write-Log "Вложение извлечено: $($attachment.file_name)" -Severity Debug -Category 'Metadata'
            }
        }
        catch {
            Write-Log "Не удалось извлечь вложение $($attachment.id): $_" -Severity Warning -Category 'Metadata'
        }
    }
}

function Get-Subtitles {
    [CmdletBinding()]
    param(
        [object]$FileInfo,
        [hashtable]$Job,
        [string]$MetadataDir
    )
    
    $subtitleTracks = $FileInfo.tracks | Where-Object { $_.type -eq 'subtitles' } | Sort-Object { [int]$_.id }
    
    if ($subtitleTracks.Count -eq 0) {
        Write-Log "Субтитры не обнаружены" -Severity Verbose -Category 'Subtitles'
        return
    }
    
    Write-Log "Извлечение субтитров ($($subtitleTracks.Count) дорожек)" -Severity Information -Category 'Subtitles'
    
    $subtitleIndex = 0
    foreach ($track in $subtitleTracks) {
        try {
            $lang = if ($track.properties.language -eq 'und') { '' } else { $track.properties.language }
            $ext = Get-SubtitleExtension -Codec $track.codec
            
            # Формирование имени файла
            $subFileName = "sID{0}_[{1}]_{{`{2`}}}{3}{4}.{5}" -f 
                $track.id,
                $lang,
                (Get-SafeFileName -FileName $track.properties.track_name),
                ($track.properties.default_track ? '+' : '-'),
                ($track.properties.forced_track ? 'F' : ''),
                $ext
            
            $subFile = Join-Path -Path $MetadataDir -ChildPath $subFileName
            
            # Извлечение субтитров с учетом обрезки
            Get-SubtitleTrack -Job $Job -TrackIndex $subtitleIndex -OutputFile $subFile -TrackId $track.id
            
            if (Test-Path -LiteralPath $subFile -PathType Leaf) {
                $subInfo = @{
                    Path     = $subFile
                    Language = $lang
                    Name     = $track.properties.track_name
                    Codec    = $track.codec
                    Default  = $track.properties.default_track
                    Forced   = $track.properties.forced_track
                }
                
                $Job.Metadata.Subtitles.Add($subInfo)
                Write-Log "Субтитры извлечены: $([IO.Path]::GetFileName($subFile))" -Severity Information -Category 'Subtitles'
            }
            
            $subtitleIndex++
        }
        catch {
            Write-Log "Ошибка при извлечении субтитров (ID: $($track.id)): $_" -Severity Warning -Category 'Subtitles'
            $subtitleIndex++
        }
    }
}

function Get-SubtitleTrack {
    [CmdletBinding()]
    param(
        [hashtable]$Job,
        [int]$TrackIndex,
        [string]$OutputFile,
        [int]$TrackId
    )
    
    # Параметры обрезки
    $trimParams = @()
    if ($Job.TrimStartSeconds -gt 0) {
        $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Job.TrimDurationSeconds -gt 0) {
        $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    
    # Сначала пробуем через FFmpeg
    $ffmpegArgs = @(
        "-y", "-hide_banner", "-loglevel", "error",
        "-i", $Job.VideoPath,
        $trimParams,
        "-map", "0:s:$TrackIndex",
        "-c", "copy",
        $OutputFile
    )
    
    & $global:VideoTools.FFmpeg @ffmpegArgs
    
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $OutputFile)) {
        # Fallback: используем mkvextract
        Write-Log "FFmpeg не справился, используем mkvextract для субтитров ID: $TrackId" -Severity Warning -Category 'Subtitles'
        & $global:VideoTools.MkvExtract $Job.VideoPath tracks "$($TrackId):$OutputFile" *>$null
    }
}

function Get-Chapters {
    [CmdletBinding()]
    param(
        [hashtable]$Job,
        [string]$MetadataDir
    )
    
    $chaptersFile = Join-Path -Path $MetadataDir -ChildPath "$($Job.BaseName)_chapters.xml"
    
    try {
        & $global:VideoTools.MkvExtract $Job.VideoPath chapters $chaptersFile *>$null
        
        if (Test-Path -LiteralPath $chaptersFile -PathType Leaf) {
            Write-Log "Главы успешно извлечены" -Severity Information -Category 'Metadata'
        } else {
            Write-Log "Главы не обнаружены" -Severity Verbose -Category 'Metadata'
        }
    }
    catch {
        Write-Log "Не удалось извлечь главы: $_" -Severity Warning -Category 'Metadata'
    }
}

function Get-NfoFile {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    # Поиск NFO файла в различных местах
    $nfoFile = Find-NfoFile -Job $Job
    
    if ($nfoFile -and (Test-Path -LiteralPath $nfoFile -PathType Leaf)) {
        $nfoTagsFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName)_nfo_tags.xml"
        $fields = ConvertFrom-NfoToXml -NfoFile $nfoFile -OutputFile $nfoTagsFile
        $Job.NFOFields = $fields
        $Job.NfoTags = $nfoTagsFile
        $Job.TempFiles.Add($nfoTagsFile)
        Write-Log "NFO файл обработан: $([System.IO.Path]::GetFileName($nfoFile))" -Severity Information -Category 'Metadata'
    } else {
        # Если NFO нет, копируем теги из исходного MKV файла
        Write-Log "NFO файл отсутствует, копируем теги из MKV" -Severity Information -Category 'Metadata'
        $Job.NfoTags = Copy-TagsFromSource -Job $Job
    }
}

function Find-NfoFile {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    # 1. В рабочей директории (скопированный ранее)
    $nfoFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName).nfo"
    
    if (Test-Path -LiteralPath $nfoFile -PathType Leaf) {
        return $nfoFile
    }
    
    # 2. Рядом с оригинальным файлом
    $nfoFile = [IO.Path]::ChangeExtension($Job.OriginalPath, "nfo")
    
    if (Test-Path -LiteralPath $nfoFile -PathType Leaf) {
        return $nfoFile
    }
    
    # 3. В директории исходного файла с другим именем
    $sourceDir = [IO.Path]::GetDirectoryName($Job.OriginalPath)
    $potentialNfo = Get-ChildItem -Path $sourceDir -Filter "*.nfo" | Select-Object -First 1
    if ($potentialNfo) {
        return $potentialNfo.FullName
    }
    
    return $null
}

# ============================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# ============================================

function Find-CoverFile {
    [CmdletBinding()]
    param(
        [hashtable]$Job,
        [string]$SourceDir
    )
    
    $coverFiles = @('cover.jpg', 'cover.png', 'cover.webp', 'folder.jpg', 'folder.png', 'folder.webp')
    $coverRegexPatterns = @(
        'season\d+\-poster\.(jpg|jpeg|png|webp)',
        'poster\.(jpg|jpeg|png|webp)',
        'cover-\d+\.(jpg|jpeg|png|webp)'
    )
    
    $coverFile = $null
    
    # Сначала проверяем статические имена файлов
    foreach ($coverName in $coverFiles) {
        $potentialCover = Join-Path -Path $SourceDir -ChildPath $coverName
        if (Test-Path -LiteralPath $potentialCover -PathType Leaf) {
            $coverFile = $potentialCover
            Write-Log "Найдена обложка: $coverFile" -Severity Information -Category 'Metadata'
            break
        }
    }
    
    # Если не нашли, ищем по регулярным выражениям
    if (-not $coverFile) {
        foreach ($pattern in $coverRegexPatterns) {
            try {
                $allFiles = Get-ChildItem -Path $SourceDir -File | Where-Object { 
                    $_.Name -match $pattern 
                }
                
                if ($allFiles.Count -gt 0) {
                    $coverFile = ($allFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
                    Write-Log "Найдена обложка по шаблону '$pattern': $coverFile" -Severity Information -Category 'Metadata'
                    break
                }
            }
            catch {
                Write-Log "Ошибка при обработке шаблона '$pattern': $_" -Severity Warning -Category 'Metadata'
            }
        }
    }
    
    # Копируем обложку во временную директорию
    if ($coverFile) {
        $coverExt = [IO.Path]::GetExtension($coverFile)
        $coverDest = Join-Path -Path $Job.Metadata.TempDir -ChildPath "cover$coverExt"
        Copy-Item -LiteralPath $coverFile -Destination $coverDest -Force
        $Job.Metadata.CoverFile = $coverDest
        $Job.TempFiles.Add($coverDest)
        Write-Log "Обложка скопирована во временную директорию" -Severity Information -Category 'Metadata'
    } else {
        Write-Log "Обложка не найдена" -Severity Warning -Category 'Metadata'
    }
}

function Get-SubtitleExtension {
    [CmdletBinding()]
    param([string]$Codec)
    
    switch ($Codec) {
        'SubStationAlpha' { 'ass' }
        'HDMV PGS'       { 'sup' }
        'VobSub'         { 'sub' }
        'SubRip/SRT'     { 'srt' }
        default          { 'srt' }
    }
}

function Get-FileTitle {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    if (-not $Job.NFOFields) {
        return [System.IO.Path]::GetFileNameWithoutExtension($Job.OriginalPath)
    }
    
    $airDateFormatted = if ($Job.NFOFields.AIR_DATE) { 
        $Job.NFOFields.AIR_DATE 
    } else { 
        $Job.NFOFields.DATE_RELEASED ?? "Unknown" 
    }
    
    $fileTitle = "{0} - s{1:00}e{2:00} - {3} [{4}]" -f `
        $Job.NFOFields.SHOWTITLE,
        [int]$Job.NFOFields.SEASON_NUMBER,
        [int]$Job.NFOFields.PART_NUMBER,
        $Job.NFOFields.TITLE,
        $airDateFormatted
    
    return $fileTitle
}

function Build-BaseMkvMergeArgs {
    [CmdletBinding()]
    param(
        [string]$OutputFile,
        [string]$VideoFile,
        [string]$Title
    )
    
    $mkvMergeArgs = @(
        '--ui-language', 'en',
        '--priority', 'lower',
        '--output', $OutputFile,
        $VideoFile
    )
    
    if (-not [string]::IsNullOrWhiteSpace($Title)) {
        $mkvMergeArgs += @('--title', $Title)
    }
    
    $mkvMergeArgs += @('--no-date', '--no-track-tags')
    return $mkvMergeArgs
}

function Add-AudioTracksToArgs {
    [CmdletBinding()]
    param(
        [array]$MkvArgs,
        [array]$AudioTracks
    )
    
    $resultArgs = $MkvArgs.Clone()
    
    foreach ($audioTrack in $AudioTracks) {
        $resultArgs += Build-AudioTrackArgs -AudioTrack $audioTrack
        $resultArgs += $audioTrack.Path
    }
    
    return $resultArgs
}

function Build-AudioTrackArgs {
    [CmdletBinding()]
    param([object]$AudioTrack)
    
    $mkvMergeArgs = @('--no-track-tags')
    
    if ($audioTrack.Language) {
        $mkvMergeArgs += @('--language', "0:$($audioTrack.Language)")
    }
    
    if ($audioTrack.Title) {
        $mkvMergeArgs += @('--track-name', "0:$($audioTrack.Title)")
    }
    
    $mkvMergeArgs += @(
        '--default-track-flag', "0:$(if ($audioTrack.Default) {'yes'} else {'no'})",
        '--forced-display-flag', "0:$(if ($audioTrack.Forced) {'yes'} else {'no'})"
    )
    
    return $mkvMergeArgs
}

function Add-SubtitlesToArgs {
    [CmdletBinding()]
    param(
        [array]$MkvArgs,
        [System.Collections.Generic.List[object]]$Subtitles
    )
    
    $resultArgs = $MkvArgs.Clone()
    
    foreach ($subTrack in $Subtitles) {
        $resultArgs += Build-SubtitleTrackArgs -SubTrack $subTrack
        $resultArgs += $subTrack.Path
    }
    
    return $resultArgs
}

function Build-SubtitleTrackArgs {
    [CmdletBinding()]
    param([object]$SubTrack)
    
    if ($subTrack.Language) {
        $mkvMergeArgs += @('--language', "0:$($subTrack.Language)")
    }
    
    if ($subTrack.Name) {
        $mkvMergeArgs += @('--track-name', "0:$($subTrack.Name)")
    }
    
    $mkvMergeArgs += @(
        '--default-track-flag', "0:$(if ($subTrack.Default) {'yes'} else {'no'})",
        '--forced-display-flag', "0:$(if ($subTrack.Forced) {'yes'} else {'no'})"
    )
    
    return $mkvMergeArgs
}

function Add-ChaptersToArgs {
    [CmdletBinding()]
    param(
        [array]$MkvArgs,
        [hashtable]$Job
    )
    
    $resultArgs = $MkvArgs.Clone()
    $chaptersFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_chapters.xml"
    
    if (Test-Path -LiteralPath $chaptersFile -PathType Leaf) {
        $resultArgs += @('--chapters', $chaptersFile)
    }
    
    return $resultArgs
}

function Add-TagsToArgs {
    [CmdletBinding()]
    param(
        [array]$MkvArgs,
        [string]$TagsFile
    )
    
    $resultArgs = $MkvArgs.Clone()
    
    if ($TagsFile -and (Test-Path -LiteralPath $TagsFile -PathType Leaf)) {
        $resultArgs += @('--global-tags', $TagsFile)
    }
    
    return $resultArgs
}

function Invoke-MkvMerge {
    [CmdletBinding()]
    param([array]$Arguments)
    
    & $global:VideoTools.MkvMerge @Arguments
    
    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка mkvmerge (код $LASTEXITCODE)"
    }
}

function Add-CoverToMKV {
    [CmdletBinding()]
    param([hashtable]$Job)
    
    if (-not $Job.Metadata.CoverFile -or -not (Test-Path -LiteralPath $Job.Metadata.CoverFile -PathType Leaf)) {
        Write-Log "Обложка не найдена, пропускаем добавление" -Severity Verbose -Category 'Muxing'
        return
    }
    
    $coverExt = [IO.Path]::GetExtension($Job.Metadata.CoverFile).ToLower()
    $mimeType = switch ($coverExt) {
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.png'  { 'image/png' }
        '.webp' { 'image/webp' }
        default { 'image/jpeg' }
    }
    
    $coverArgs = @(
        $Job.FinalOutput,
        '--attachment-name', 'cover',
        '--attachment-mime-type', $mimeType,
        '--add-attachment', $Job.Metadata.CoverFile
    )
    
    Write-Log "Добавление обложки: $($Job.Metadata.CoverFile)" -Severity Information -Category 'Muxing'
    
    & $global:VideoTools.MkvPropedit @coverArgs
    
    if ($LASTEXITCODE -ne 0) {
        Write-Log "Предупреждение: не удалось добавить обложку (код $LASTEXITCODE)" -Severity Warning -Category 'Muxing'
    } else {
        Write-Log "Обложка успешно добавлена" -Severity Success -Category 'Muxing'
    }
}

# ============================================
# ФУНКЦИИ РАБОТЫ С ТЕГАМИ
# ============================================

function Copy-TagsFromSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        Write-Log "Копирование тегов из исходного файла" -Severity Information -Category 'Metadata'
        
        # Создаем временный файл для тегов
        $tagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_source_tags.xml"
        $sourceTagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_source_tags.txt"
        
        # Используем mkvpropedit для получения тегов
        $mkvpropeditArgs = @('--export-tags', 'xml:' + $sourceTagsFile, $Job.VideoPath)
        
        & $global:VideoTools.MkvPropedit @mkvpropeditArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $sourceTagsFile -PathType Leaf)) {
            Copy-Item -LiteralPath $sourceTagsFile -Destination $tagsFile -Force
            Write-Log "Теги успешно скопированы из исходного файла" -Severity Success -Category 'Metadata'
        } else {
            # Альтернативный способ через mkvmerge
            Write-Log "Не удалось извлечь теги через mkvpropedit, пробуем через mkvmerge" -Severity Warning -Category 'Metadata'
            $tagsContent = Get-TagsFromMkvMerge -VideoPath $Job.VideoPath
            
            if ($tagsContent) {
                ConvertTo-TagsXml -TagsContent $tagsContent -OutputFile $tagsFile
            } else {
                Write-Log "Не удалось извлечь теги из исходного файла" -Severity Warning -Category 'Metadata'
                return $null
            }
        }
        
        # Добавляем файл тегов в список временных файлов
        $Job.TempFiles.Add($tagsFile)
        if (Test-Path -LiteralPath $sourceTagsFile) {
            $Job.TempFiles.Add($sourceTagsFile)
        }
        
        return $tagsFile
    }
    catch {
        Write-Log "Ошибка при копировании тегов из исходного файла: $_" -Severity Warning -Category 'Metadata'
        return $null
    }
}

function Get-TagsFromMkvMerge {
    [CmdletBinding()]
    param([string]$VideoPath)
    
    try {
        $mkvmergeArgs = @('--ui-language', 'en', '--identify-verbose', $VideoPath)
        $identifyOutput = & $global:VideoTools.MkvMerge @mkvmergeArgs 2>&1
        
        return ConvertFrom-MkvMergeTags -Output $identifyOutput
    }
    catch {
        Write-Log "Ошибка получения тегов через mkvmerge: $_" -Severity Warning -Category 'Metadata'
        return $null
    }
}

function ConvertFrom-MkvMergeTags {
    [CmdletBinding()]
    param([string[]]$Output)
    
    try {
        $tags = [System.Collections.Generic.List[hashtable]]::new()
        $currentTag = $null
        
        foreach ($line in $Output) {
            $line = $line.Trim()
            
            if ($line -match '^\| \+ (Tag.+)$') {
                if ($currentTag) { $tags.Add($currentTag) }
                $currentTag = @{ Name = $Matches[1].Trim(); Elements = @() }
            }
            elseif ($currentTag -and $line -match '^\|   \+ Simple.+name:\s*"([^"]+)".+string:\s*"([^"]+)"') {
                $currentTag.Elements += @{ Name = $Matches[1]; Value = $Matches[2] }
            }
            elseif ($line -match '^\|   \| \+ Tag') {
                continue  # Вложенные теги пока не обрабатываем
            }
        }
        
        if ($currentTag) { $tags.Add($currentTag) }
        return $tags
    }
    catch {
        Write-Log "Ошибка парсинга тегов из mkvmerge: $_" -Severity Warning -Category 'Metadata'
        return $null
    }
}

function ConvertTo-TagsXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][array]$TagsContent,
        [Parameter(Mandatory)][string]$OutputFile
    )
    
    try {
        $settings = [System.Xml.XmlWriterSettings]@{
            Indent = $true
            Encoding = [System.Text.Encoding]::UTF8
        }
        
        $xmlWriter = [System.Xml.XmlWriter]::Create($OutputFile, $settings)
        try {
            $xmlWriter.WriteStartDocument()
            $xmlWriter.WriteStartElement("Tags")
            
            foreach ($tag in $TagsContent) {
                $xmlWriter.WriteStartElement("Tag")
                $xmlWriter.WriteStartElement("Targets")
                $xmlWriter.WriteElementString("TargetTypeValue", "50")  # Video
                $xmlWriter.WriteEndElement() # Targets
                
                foreach ($element in $tag.Elements) {
                    $xmlWriter.WriteStartElement("Simple")
                    $xmlWriter.WriteElementString("Name", $element.Name)
                    $xmlWriter.WriteElementString("String", $element.Value)
                    $xmlWriter.WriteEndElement() # Simple
                }
                
                $xmlWriter.WriteEndElement() # Tag
            }
            
            $xmlWriter.WriteEndElement() # Tags
            $xmlWriter.WriteEndDocument()
        }
        finally {
            $xmlWriter.Close()
        }
    }
    catch {
        Write-Log "Ошибка создания XML тегов: $_" -Severity Warning -Category 'Metadata'
    }
}

function ConvertFrom-NfoToTagsXml {
    [CmdletBinding()]
    param(
        [object]$Episode,
        [string]$OutputFile
    )
    
    $fields = @{}
    $settings = [XmlWriterSettings]@{ Indent = $true; Encoding = [Text.Encoding]::UTF8 }
    $writer = [XmlWriter]::Create($OutputFile, $settings)
    
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement("Tags")
        
        # Основные поля
        $basicFields = @{
            TITLE            = $episode.title
            ORIGINAL_TITLE   = $episode.originaltitle
            SUMMARY          = $episode.plot
            DATE_RELEASED    = $episode.premiered
            AIR_DATE         = $episode.aired
            PART_NUMBER      = $episode.episode
            SEASON_NUMBER    = $episode.season
            SHOWTITLE        = $episode.showtitle
        }
        
        foreach ($field in $basicFields.GetEnumerator()) {
            if (-not [string]::IsNullOrEmpty($field.Value)) {
                $fields[$field.Key] = $field.Value
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", $field.Key)
                $writer.WriteElementString("String", $field.Value)
                $writer.WriteEndElement()
                $writer.WriteEndElement()
            }
        }
        
        # Студии
        foreach ($studio in $episode.studio) {
            $writer.WriteStartElement("Tag")
            $writer.WriteStartElement("Simple")
            $writer.WriteElementString("Name", "STUDIO")
            $writer.WriteElementString("String", $studio)
            $writer.WriteEndElement()
            $writer.WriteEndElement()
        }
        
        # Режиссеры
        foreach ($director in $episode.director) {
            $writer.WriteStartElement("Tag")
            $writer.WriteStartElement("Simple")
            $writer.WriteElementString("Name", "DIRECTOR")
            $writer.WriteElementString("String", $director.InnerText)
            $writer.WriteEndElement()
            $writer.WriteEndElement()
        }
        
        # Уникальные идентификаторы
        foreach ($uniqueid in $episode.uniqueid) {
            $type = $uniqueid.type
            $value = $uniqueid.InnerText
            
            if ($type -and $value) {
                $tagName = $type.ToUpper()
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", $tagName)
                $writer.WriteElementString("String", $value)
                $writer.WriteEndElement()
                $writer.WriteEndElement()
            }
        }
        
        $writer.WriteEndElement()
        $writer.WriteEndDocument()
    }
    finally {
        $writer.Close()
    }
    
    return $fields
}

function Add-EncoderParamsTag {
    <#
    .SYNOPSIS
        Добавляет тег EncoderParams с параметрами кодирования в MKV файл
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        # Подготавливаем параметры энкодера для записи в тег
        $encoderParamsForTag = @{
            Encoder = $Job.Encoder
            EncoderName = $Job.Encoder
            EncoderPath = if ($Job.EncoderPath) { [System.IO.Path]::GetFileName($Job.EncoderPath) } else { 'unknown' }
            EncoderParams = $Job.EncoderParams
            DateEncoded = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
            Quality = if ($Job.Quality) { $Job.Quality } else { 'N/A' }
        }
        
        # Конвертируем в JSON со сжатием (убираем пробелы и переводы строк)
        $jsonParams = $encoderParamsForTag | ConvertTo-Json -Compress -Depth 3
        
        # Ограничиваем длину JSON (некоторые теговые системы имеют ограничения)
        if ($jsonParams.Length -gt 8000) {
            # Если слишком длинный, оставляем только основные параметры
            $simpleParams = @{
                Encoder = $Job.Encoder
                EncoderParams = $Job.EncoderParams
                DateEncoded = $encoderParamsForTag.DateEncoded
            }
            $jsonParams = $simpleParams | ConvertTo-Json -Compress -Depth 2
        }
        
        Write-Log "Добавление тега EncoderParams ($($jsonParams.Length) символов)" -Severity Information -Category 'Muxing'
        Write-Verbose "EncoderParams JSON: $jsonParams"
        
        # Создаем временный XML файл с тегами
        $tempTagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "encoder_params.xml"
        
        # Формируем XML для mkvpropedit
        $xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE Tags SYSTEM "matroskatags.dtd">
<Tags>
  <Tag>
    <Targets>
      <TargetTypeValue>50</TargetTypeValue>
    </Targets>
    <Simple>
      <Name>ENCODERPARAMS</Name>
      <String>$([Security.SecurityElement]::Escape($jsonParams))</String>
    </Simple>
  </Tag>
</Tags>
"@
        
        Set-Content -LiteralPath $tempTagsFile -Value $xmlContent -Encoding UTF8
        
        # Добавляем тег через mkvpropedit
        $mkvpropeditArgs = @(
            $Job.FinalOutput,
            '--tags', "global:$tempTagsFile"
        )
        
        Write-Debug "mkvpropedit $($mkvpropeditArgs -join ' ')"
        # & $global:VideoTools.MkvPropedit @mkvpropeditArgs
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Предупреждение: не удалось добавить тег EncoderParams (код $LASTEXITCODE)" `
                -Severity Warning -Category 'Muxing'
        } else {
            Write-Log "Тег EncoderParams успешно добавлен" -Severity Success -Category 'Muxing'
            
            # Добавляем файл тегов в список временных файлов
            $Job.TempFiles.Add($tempTagsFile)
        }
    }
    catch {
        Write-Log "Ошибка при добавлении тега EncoderParams: $_" -Severity Warning -Category 'Muxing'
        # Не бросаем исключение, так как это дополнительная информация
    }
}

# ============================================
# ЭКСПОРТ ФУНКЦИЙ
# ============================================

Export-ModuleMember -Function `
    Invoke-ProcessMetaData, `
    Complete-MediaFile, `
    ConvertFrom-NfoToXml