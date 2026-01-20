<#
.SYNOPSIS
    Модуль для обработки метаданных мультимедиа
#>

using namespace System.Xml
using namespace System.Text

function Copy-TagsFromSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        Write-Log "NFO файл отсутствует, копирую теги из исходного файла" -Severity Information -Category 'Metadata'
        
        # Создаем временный файл для тегов
        $tagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_source_tags.xml"
        
        # Извлекаем теги из исходного файла с помощью mkvpropedit
        $sourceTagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_source_tags.txt"
        
        # Используем mkvpropedit для получения тегов в формате XML
        $mkvpropeditArgs = @(
            '--export-tags', 'xml:' + $sourceTagsFile,
            $Job.VideoPath
        )
        
        Write-Log "Извлечение тегов из исходного файла: $($Job.VideoPath)" -Severity Debug -Category 'Metadata'
        & $global:VideoTools.MkvPropedit @mkvpropeditArgs 2>&1 | Out-Null
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Не удалось извлечь теги через mkvpropedit, пробую через mkvmerge" -Severity Warning -Category 'Metadata'
            
            # Альтернативный способ через mkvmerge
            $mkvmergeArgs = @(
                '--ui-language', 'en',
                '--identify-verbose', $Job.VideoPath
            )
            
            $identifyOutput = & $global:VideoTools.MkvMerge @mkvmergeArgs 2>&1
            $tagsContent = Parse-TagsFromMkvMerge -Output $identifyOutput
            
            if ($tagsContent) {
                # Создаем XML файл с тегами
                Create-TagsXml -TagsContent $tagsContent -OutputFile $tagsFile
            } else {
                Write-Log "Не удалось извлечь теги из исходного файла" -Severity Warning -Category 'Metadata'
                return $null
            }
        } else {
            # Если mkvpropedit успешно создал файл, копируем его
            if (Test-Path -LiteralPath $sourceTagsFile -PathType Leaf) {
                Copy-Item -LiteralPath $sourceTagsFile -Destination $tagsFile -Force
                Write-Log "Теги успешно скопированы из исходного файла" -Severity Success -Category 'Metadata'
            } else {
                Write-Log "Файл тегов не создан mkvpropedit" -Severity Warning -Category 'Metadata'
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

function Parse-TagsFromMkvMerge {
    [CmdletBinding()]
    param([string[]]$Output)
    
    try {
        $tags = [System.Collections.Generic.List[hashtable]]::new()
        $currentTag = $null
        
        foreach ($line in $Output) {
            $line = $line.Trim()
            
            # Ищем строки с тегами
            if ($line -match '^\| \+ (Tag.+)$') {
                if ($currentTag) {
                    $tags.Add($currentTag)
                }
                $currentTag = @{ Name = $Matches[1].Trim(); Elements = @() }
            }
            elseif ($currentTag -and $line -match '^\|   \+ Simple.+name:\s*"([^"]+)".+string:\s*"([^"]+)"') {
                $currentTag.Elements += @{
                    Name = $Matches[1]
                    Value = $Matches[2]
                }
            }
            elseif ($line -match '^\|   \| \+ Tag') {
                # Вложенные теги пока не обрабатываем
                continue
            }
        }
        
        if ($currentTag) {
            $tags.Add($currentTag)
        }
        
        return $tags
    }
    catch {
        Write-Verbose "Ошибка парсинга тегов из mkvmerge: $_"
        return $null
    }
}

function Create-TagsXml {
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
                
                # Добавляем тип цели (50 = Video, 60 = Audio, etc.)
                $xmlWriter.WriteElementString("TargetTypeValue", "50")
                
                $xmlWriter.WriteEndElement() # Targets
                
                # Добавляем Simple элементы
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
        
        Write-Verbose "Создан XML файл тегов: $OutputFile"
    }
    catch {
        Write-Verbose "Ошибка создания XML тегов: $_"
    }
}

function Invoke-ProcessMetaData {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)

    try {
        Write-Log "Начало обработки метаданных" -Severity Information -Category 'Metadata'
        
        $metadataDir = Join-Path -Path $Job.WorkingDir -ChildPath "meta"
        New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
        $Job.Metadata = @{ 
            TempDir = $metadataDir
            Attachments = [System.Collections.Generic.List[object]]::new()
        }

        # Поиск файла обложки в директории исходного файла
        $coverFiles = @('cover.jpg', 'cover.png', 'cover.webp', 'folder.jpg', 'folder.png', 'folder.webp')
        $coverRegexPatterns = @(
            'season\d+\-poster\.(jpg|jpeg|png|webp)',
            'poster\.(jpg|jpeg|png|webp)',
            'cover-\d+\.(jpg|jpeg|png|webp)'
        )
        
        $coverFile = $null
        $sourceDir = [IO.Path]::GetDirectoryName($Job.VideoPath)
        
        # Сначала проверяем статические имена файлов
        foreach ($coverName in $coverFiles) {
            $potentialCover = Join-Path -Path $sourceDir -ChildPath $coverName
            if (Test-Path -LiteralPath $potentialCover -PathType Leaf) {
                $coverFile = $potentialCover
                Write-Log "Найдена обложка: $coverFile" -Severity Information -Category 'Metadata'
                break
            }
        }
        
        # Если не нашли статические имена, ищем по регулярным выражениям
        if (-not $coverFile) {
            Write-Log "Поиск обложки по регулярным выражениям..." -Severity Information -Category 'Metadata'
            
            foreach ($pattern in $coverRegexPatterns) {
                try {
                    # Получаем все файлы в директории и фильтруем по регулярному выражению
                    $allFiles = Get-ChildItem -Path $sourceDir -File | Where-Object { 
                        $_.Name -match $pattern 
                    }
                    
                    if ($allFiles.Count -gt 0) {
                        # Сортируем по дате изменения (новые сначала) и берем первый файл
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
        
        # Копируем обложку во временную директорию, если найдена
        if ($coverFile) {
            $coverExt = [IO.Path]::GetExtension($coverFile)
            $coverDest = Join-Path -Path $metadataDir -ChildPath "cover$coverExt"
            Copy-Item -LiteralPath $coverFile -Destination $coverDest -Force
            $Job.Metadata.CoverFile = $coverDest
            $Job.TempFiles.Add($coverDest)
            Write-Log "Обложка скопирована во временную директорию" -Severity Information -Category 'Metadata'
        } else {
            Write-Log "Обложка не найдена" -Severity Warning -Category 'Metadata'
        }

        # Извлечение информации
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $jsonInfo = & $global:VideoTools.MkvMerge -J $Job.VideoPath | ConvertFrom-Json
        [Console]::OutputEncoding = $originalEncoding

        # Обработка вложений и субтитров
        Invoke-ProcessAttachments -jsonInfo $jsonInfo -Job $Job -metadataDir $metadataDir
        Invoke-ProcessSubtitles -jsonInfo $jsonInfo -Job $Job -metadataDir $metadataDir

        # Извлечение глав
        $chaptersFile = Join-Path -Path $metadataDir -ChildPath "$($Job.BaseName)_chapters.xml"
        & $global:VideoTools.MkvExtract $Job.VideoPath chapters $chaptersFile *>$null

        # Обработка NFO файла
        $nfoFile = [IO.Path]::ChangeExtension($Job.VideoPath, "nfo")
        if (Test-Path -LiteralPath $nfoFile -PathType Leaf) {
            $nfoTagsFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName)_nfo_tags.xml"
            $fields = ConvertFrom-NfoToXml -NfoFile $nfoFile -OutputFile $nfoTagsFile
            $Job.NFOFields = $fields
            $Job.NfoTags = $nfoTagsFile
            $Job.TempFiles.Add($nfoTagsFile)
        } else {
            # Если NFO нет, копируем теги из исходного MKV файла
            Write-Log "NFO файл отсутствует, будет выполнена попытка копирования тегов из исходного MKV" -Severity Information -Category 'Metadata'
            $Job.NfoTags = Copy-TagsFromSource -Job $Job
        }

        $Job.TempFiles.Add($metadataDir)
        Write-Log "Обработка метаданных завершена" -Severity Success -Category 'Metadata'
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке метаданных: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

function Invoke-ProcessMP4Metadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)

    try {
        Write-Log "Обработка метаданных MP4 файла" -Severity Information -Category 'Metadata'
        
        $metadataDir = Join-Path -Path $Job.WorkingDir -ChildPath "meta"
        New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
        $Job.Metadata = @{ 
            TempDir = $metadataDir
            Attachments = [System.Collections.Generic.List[object]]::new()
        }

        # Поиск обложки
        $coverFiles = @('cover.jpg', 'cover.png', 'cover.webp', 'folder.jpg', 'folder.png', 'folder.webp')
        $coverFile = $null
        
        foreach ($coverName in $coverFiles) {
            $potentialCover = Join-Path -Path ([IO.Path]::GetDirectoryName($Job.VideoPath)) -ChildPath $coverName
            if (Test-Path -LiteralPath $potentialCover -PathType Leaf) {
                $coverFile = $potentialCover
                Write-Log "Найдена обложка: $coverFile" -Severity Information -Category 'Metadata'
                break
            }
        }
        
        # Копируем обложку
        if ($coverFile) {
            $coverExt = [IO.Path]::GetExtension($coverFile)
            $coverDest = Join-Path -Path $metadataDir -ChildPath "cover$coverExt"
            Copy-Item -LiteralPath $coverFile -Destination $coverDest -Force
            $Job.Metadata.CoverFile = $coverDest
            $Job.TempFiles.Add($coverDest)
        }

        # Извлечение информации через FFprobe для MP4
        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -print_format json -show_format -show_streams $Job.VideoPath
        $jsonInfo = $ffprobeOutput | ConvertFrom-Json
        [Console]::OutputEncoding = $originalEncoding

        # Обработка аудио и субтитров для MP4
        Invoke-ProcessMP4Streams -jsonInfo $jsonInfo -Job $Job -metadataDir $metadataDir

        # Извлечение глав (если есть)
        $chaptersFile = Join-Path -Path $metadataDir -ChildPath "$($Job.BaseName)_chapters.xml"
        $tempChaptersFile = Join-Path -Path $metadataDir -ChildPath "$($Job.BaseName)_chapters_ffmetadata.txt"
        
        try {
            # Извлекаем главы в формате FFmetadata
            & $global:VideoTools.FFmpeg -i $Job.VideoPath -f ffmetadata $tempChaptersFile 2>&1 | Out-Null
            
            if (Test-Path -LiteralPath $tempChaptersFile -PathType Leaf) {
                # Конвертируем в XML формат для mkvmerge
                Convert-MP4ChaptersToXML -InputFile $tempChaptersFile -OutputFile $chaptersFile
                
                if (Test-Path -LiteralPath $chaptersFile -PathType Leaf) {
                    Write-Log "Главы MP4 успешно извлечены и сконвертированы" -Severity Information -Category 'Metadata'
                    $Job.TempFiles.Add($tempChaptersFile)
                } else {
                    Write-Log "Не удалось создать файл глав XML" -Severity Warning -Category 'Metadata'
                }
            } else {
                Write-Log "Главы не найдены в MP4 файле" -Severity Verbose -Category 'Metadata'
            }
        } 
        catch {
            Write-Log "Ошибка при извлечении глав MP4: $_" -Severity Warning -Category 'Metadata'
        }

        # Обработка NFO файла
        $nfoFile = [IO.Path]::ChangeExtension($Job.VideoPath, "nfo")
        if (Test-Path -LiteralPath $nfoFile -PathType Leaf) {
            $nfoTagsFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName)_nfo_tags.xml"
            $fields = ConvertFrom-NfoToXml -NfoFile $nfoFile -OutputFile $nfoTagsFile
            $Job.NFOFields = $fields
            $Job.NfoTags = $nfoTagsFile
            $Job.TempFiles.Add($nfoTagsFile)
        } else {
            # Для MP4 файлов тоже копируем теги из исходника
            Write-Log "NFO файл отсутствует, будет выполнена попытка копирования тегов из MP4" -Severity Information -Category 'Metadata'
            $Job.NfoTags = Copy-MP4TagsFromSource -Job $Job
        }

        $Job.TempFiles.Add($metadataDir)
        Write-Log "Обработка метаданных MP4 завершена" -Severity Success -Category 'Metadata'
        return $Job
    }
    catch {
        Write-Log "Ошибка при обработке метаданных MP4: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

function Copy-MP4TagsFromSource {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)
    
    try {
        Write-Log "Копирование тегов из MP4 файла" -Severity Information -Category 'Metadata'
        
        $tagsFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_mp4_tags.xml"
        
        # Извлекаем метаданные из MP4 с помощью ffprobe
        $ffprobeOutput = & $global:VideoTools.FFprobe -v error -print_format json -show_format $Job.VideoPath
        $formatInfo = $ffprobeOutput | ConvertFrom-Json
        
        if ($formatInfo.format.tags) {
            $settings = [System.Xml.XmlWriterSettings]@{
                Indent = $true
                Encoding = [System.Text.Encoding]::UTF8
            }
            
            $xmlWriter = [System.Xml.XmlWriter]::Create($tagsFile, $settings)
            try {
                $xmlWriter.WriteStartDocument()
                $xmlWriter.WriteStartElement("Tags")
                $xmlWriter.WriteStartElement("Tag")
                $xmlWriter.WriteStartElement("Targets")
                $xmlWriter.WriteElementString("TargetTypeValue", "50")
                $xmlWriter.WriteEndElement() # Targets
                
                foreach ($tag in $formatInfo.format.tags.PSObject.Properties) {
                    $xmlWriter.WriteStartElement("Simple")
                    $xmlWriter.WriteElementString("Name", $tag.Name.ToUpper())
                    $xmlWriter.WriteElementString("String", $tag.Value)
                    $xmlWriter.WriteEndElement() # Simple
                }
                
                $xmlWriter.WriteEndElement() # Tag
                $xmlWriter.WriteEndElement() # Tags
                $xmlWriter.WriteEndDocument()
                
                Write-Log "Теги MP4 успешно извлечены" -Severity Success -Category 'Metadata'
                $Job.TempFiles.Add($tagsFile)
                return $tagsFile
            }
            finally {
                $xmlWriter.Close()
            }
        } else {
            Write-Log "В MP4 файле не найдены теги" -Severity Warning -Category 'Metadata'
            return $null
        }
    }
    catch {
        Write-Log "Ошибка при копировании тегов из MP4: $_" -Severity Warning -Category 'Metadata'
        return $null
    }
}

function Complete-MediaFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Job)

    $airDateFormatted = if ($job.NFOFields.AIR_DATE) { 
        $job.NFOFields.AIR_DATE 
    } else { 
        $job.NFOFields.DATE_RELEASED ?? "Unknown" 
    }

    try {
        Write-Log "Начало создания итогового файла" -Severity Information -Category 'Muxing'
        
        # Формируем заголовок
        if ($job.NFOFields) {
            $fileTitle = "{0} - s{1:00}e{2:00} - {3} [{4}]" -f `
                $job.NFOFields.SHOWTITLE,
                [int]$job.NFOFields.SEASON_NUMBER,
                [int]$job.NFOFields.PART_NUMBER,
                $job.NFOFields.TITLE,
                $airDateFormatted
        } else {
            $fileTitle = [System.IO.Path]::GetFileNameWithoutExtension($job.VideoPath)
        }
        
        $mkvArgs = @(
            '--ui-language', 'en',
            '--priority', 'lower',
            '--output', $Job.FinalOutput,
            $Job.VideoOutput
            $(if (-not [string]::IsNullOrWhiteSpace($fileTitle) ) { @('--title', $fileTitle) })
            '--no-date',
            '--no-track-tags'
        )

        # Аудиодорожки
        foreach ($audioTrack in $Job.AudioOutputs) {
            $mkvArgs += @(
                '--no-track-tags'
                $(if ($audioTrack.Language) { @('--language',   "0:$($audioTrack.Language)") })
                $(if ($audioTrack.Title)    { @('--track-name', "0:$($audioTrack.Title)") })
                '--default-track-flag', "0:$(if ($audioTrack.Default) {'yes'} else {'no'})",
                '--forced-display-flag', "0:$(if ($audioTrack.Forced) {'yes'} else {'no'})",
                $audioTrack.Path
            )
        }

        # Субтитры
        $subtitleTracks = $Job.Metadata.GetEnumerator() | Where-Object { $_.Key -match "^Subtitle_\d+" } | Sort-Object { [int]($_.Key -replace '\D','') }
        
        foreach ($subTrack in $subtitleTracks) {
            $sub = $subTrack.Value
            $mkvArgs += @(
                '--language', "0:$($sub.Language)",
                $(if ($sub.Name) { @('--track-name', "0:$($sub.Name)") }),
                '--default-track-flag', "0:$(if ($sub.Default) {'yes'} else {'no'})",
                '--forced-display-flag', "0:$(if ($sub.Forced) {'yes'} else {'no'})",
                $sub.Path
            )
        }

        # Главы
        $chaptersFile = Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_chapters.xml"
        if (Test-Path -LiteralPath $chaptersFile -PathType Leaf) {
            $mkvArgs += @('--chapters', $chaptersFile)
        }

        # Обработка тегов
        $tagsFile = if ($Job.NfoTags) { 
            $Job.NfoTags 
        } else {
            # Если NFO нет, копируем теги из исходного файла
            Copy-TagsFromSource -Job $Job
        }
        
        if ($tagsFile -and (Test-Path -LiteralPath $tagsFile -PathType Leaf)) {
            $mkvArgs += @('--global-tags', $tagsFile)
        }

        Write-Log "Выполняемая команда: mkvmerge $($mkvArgs -join ' ')" -Severity Debug -Category 'Muxing'

        # Выполнение mkvmerge
        & $global:VideoTools.MkvMerge @mkvArgs
        
        if ($LASTEXITCODE -ne 0) {
            throw "Ошибка mkvmerge (код $LASTEXITCODE)"
        }

        # Обработка вложений
        foreach ($attach in $Job.Metadata['Attachments']) {
            if (Test-Path -LiteralPath $attach.Path -PathType Leaf) {
                $attachArgs = @(
                    $Job.FinalOutput,
                    '--attachment-name', $attach.Name,
                    '--attachment-mime-type', $attach.Mime,
                    '--add-attachment', $attach.Path
                )
                
                if ($attach.Description) {
                    $attachArgs += '--attachment-description', $attach.Description
                }
                
                & $global:VideoTools.MkvPropedit @attachArgs
            }
        }

        # Добавление обложки, если найдена
        if ($Job.Metadata.CoverFile -and (Test-Path -LiteralPath $Job.Metadata.CoverFile -PathType Leaf)) {
            $coverExt = [IO.Path]::GetExtension($Job.Metadata.CoverFile).ToLower()
            $mimeType = switch ($coverExt) {
                '.jpg' { 'image/jpeg' }
                '.jpeg' { 'image/jpeg' }
                '.png' { 'image/png' }
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
            }
            else {
                Write-Log "Обложка успешно добавлена" -Severity Success -Category 'Muxing'
            }
        }

        Write-Log "Файл успешно создан: $($Job.FinalOutput)" -Severity Success -Category 'Muxing'
    }
    catch {
        Write-Log "Ошибка при создании итогового файла: $_" -Severity Error -Category 'Muxing'
        throw
    }
}

function Invoke-ProcessAttachments {
    param ([object]$jsonInfo, [hashtable]$Job, [string]$metadataDir)

    foreach ($attachment in $jsonInfo.attachments) {
        try {
            # Пропускаем обложки, так как мы уже обработали их отдельно
            if ($attachment.file_name -match '^(cover|folder)\.(jpg|png|webp)$') {
                Write-Log "Пропуск вложения-обложки: $($attachment.file_name)" -Severity Verbose -Category 'Metadata'
                continue
            }

            $safeName = [IO.Path]::GetFileName($attachment.file_name) -replace '[^\w\.-]', '_'
            $outputFile = Join-Path -Path $metadataDir -ChildPath "attach_$($attachment.id)_$safeName"
            & $global:VideoTools.MkvExtract $Job.VideoPath attachments "$($attachment.id):$outputFile" *>$null

            if (Test-Path -LiteralPath $outputFile -PathType Leaf) {
                $Job.Metadata.Attachments.Add(@{
                    Path        = $outputFile
                    Name        = $attachment.file_name
                    Mime        = $attachment.content_type
                    Description = $attachment.description
                    Id          = $attachment.id
                })
                Write-Log "Вложение успешно извлечено: $outputFile" -Severity Debug -Category 'Metadata'
            }
        }
        catch {
            Write-Log "Не удалось извлечь вложение $($attachment.id): $_" -Severity Warning -Category 'Metadata'
        }
    }
}

<# function Get-SafeFileName {
    [CmdletBinding()]
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) { return [string]::Empty }
    foreach ($char in [IO.Path]::GetInvalidFileNameChars()) {
        $FileName = $FileName.Replace($char, '_')
    }
    return $FileName
} #>

function Invoke-ProcessSubtitles {
    param ([object]$jsonInfo, [hashtable]$Job, [string]$metadataDir)

    $subtitleTracks = $jsonInfo.tracks | Where-Object { $_.type -eq 'subtitles' } | Sort-Object { [int]$_.id }
    Write-Log "Найдено $($subtitleTracks.Count) дорожек субтитров" -Severity Information -Category 'Subtitles'

    # Вычисляем индексы субтитров среди всех субтитров
    $subtitleIndex = 0
    foreach ($track in $subtitleTracks) {
        try {
            $lang = if ($track.properties.language -eq 'und') { '' } else { $track.properties.language }
            $ext = switch ($track.codec) {
                'SubStationAlpha' { 'ass' }
                'HDMV PGS'       { 'sup' }
                'VobSub'         { 'sub' }
                'SubRip/SRT'     { 'srt' }
                default          { 'srt' }
            }

            $subFile = Join-Path -Path $metadataDir -ChildPath (
                "sID{0}_[{1}]_{{`{2`}}}{3}{4}.{5}" -f 
                $track.id,
                $lang,
                (Get-SafeFileName -FileName $track.properties.track_name),
                ($track.properties.default_track ? '+' : '-'),
                ($track.properties.forced_track ? 'F' : ''),
                $ext
            )

            # Параметры обрезки
            $trimParams = @()
            if ($Job.TrimStartSeconds -gt 0) {
                $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            if ($Job.TrimDurationSeconds -gt 0) {
                $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
            }

            # Используем вычисленный индекс среди субтитров
            $ffmpegArgs = @(
                "-y"
                "-hide_banner"
                "-loglevel", "error"
                "-i", $Job.VideoPath
                $trimParams
                "-map", "0:s:$subtitleIndex"  # Используем индекс среди субтитров
                "-c", "copy"
                $subFile
            )
            
            Write-Log "Извлечение субтитров (ID: $($track.id), индекс: $subtitleIndex)" -Severity Debug -Category 'Subtitles'
            & $global:VideoTools.FFmpeg $ffmpegArgs

            if (Test-Path -LiteralPath $subFile -PathType Leaf) {
                $Job.Metadata["Subtitle_$($track.id)"] = @{
                    Path     = $subFile
                    Language = $lang
                    Name     = $track.properties.track_name
                    Codec    = $track.codec
                    Default  = $track.properties.default_track
                    Forced   = $track.properties.forced_track
                }
                Write-Log "Субтитры успешно извлечены: $([IO.Path]::GetFileName($subFile))" -Severity Information -Category 'Subtitles'
            }
            else {
                Write-Log "Не удалось извлечь субтитры через FFmpeg (ID: $($track.id)), пробуем mkvextract..." -Severity Warning -Category 'Subtitles'
                
                # Fallback: используем mkvextract
                & $global:VideoTools.MkvExtract $Job.VideoPath tracks "$($track.id):$subFile" *>$null
                
                if (Test-Path -LiteralPath $subFile -PathType Leaf) {
                    $Job.Metadata["Subtitle_$($track.id)"] = @{
                        Path     = $subFile
                        Language = $lang
                        Name     = $track.properties.track_name
                        Codec    = $track.codec
                        Default  = $track.properties.default_track
                        Forced   = $track.properties.forced_track
                    }
                    Write-Log "Субтитры извлечены через mkvextract: $([IO.Path]::GetFileName($subFile))" -Severity Information -Category 'Subtitles'
                }
                else {
                    Write-Log "Не удалось извлечь субтитры даже через mkvextract (ID: $($track.id))" -Severity Error -Category 'Subtitles'
                }
            }
            
            # Увеличиваем индекс для следующего субтитра
            $subtitleIndex++
        }
        catch {
            Write-Log "Ошибка при извлечении субтитров (ID: $($track.id)): $_" -Severity Warning -Category 'Subtitles'
            $subtitleIndex++
        }
    }
}

function Invoke-ProcessMP4Streams {
    param ([object]$jsonInfo, [hashtable]$Job, [string]$metadataDir)

    # Обработка субтитров MP4
    $subtitleStreams = $jsonInfo.streams | Where-Object { $_.codec_type -eq 'subtitle' } | Sort-Object { [int]$_.index }
    Write-Log "Найдено $($subtitleStreams.Count) дорожек субтитров в MP4" -Severity Information -Category 'Subtitles'

    $subtitleIndex = 0
    foreach ($stream in $subtitleStreams) {
        try {
            $lang = if ($stream.tags.language -eq 'und') { '' } else { $stream.tags.language }
            $title = [string]::IsNullOrWhiteSpace($stream.tags.title) ? $stream.tags.handler_name : $stream.tags.title
            $ext = switch ($stream.codec_name) {
                'mov_text' { 'srt' }
                'eia_608' { 'srt' }
                'webvtt' { 'vtt' }
                default { 'srt' }
            }

            $subFile = Join-Path -Path $metadataDir -ChildPath (
                "sID{0}_[{1}]_{{`{2`}}}{3}{4}.{5}" -f 
                $stream.index,
                $lang,
                $title,
                ($stream.disposition.default -eq 1 ? '+' : '-'),
                ($stream.disposition.forced -eq 1 ? 'F' : ''),
                $ext
            )

            # Параметры обрезки
            $trimParams = @()
            if ($Job.TrimStartSeconds -gt 0) {
                $trimParams += '-ss', $Job.TrimStartSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
            }
            if ($Job.TrimDurationSeconds -gt 0) {
                $trimParams += '-t', $Job.TrimDurationSeconds.ToString('0.######', [System.Globalization.CultureInfo]::InvariantCulture)
            }

            # Извлечение субтитров
            $ffmpegArgs = @(
                "-y"
                "-hide_banner"
                "-loglevel", "error"
                "-i", $Job.VideoPath
                $trimParams
                "-map", "0:s:$subtitleIndex"
                #"-c", "copy"
                $subFile
            )
            
            Write-Log "Извлечение субтитров MP4 (индекс: $subtitleIndex)" -Severity Debug -Category 'Subtitles'
            & $global:VideoTools.FFmpeg $ffmpegArgs

            if (Test-Path -LiteralPath $subFile -PathType Leaf) {
                $Job.Metadata["Subtitle_$($stream.index)"] = @{
                    Path     = $subFile
                    Language = $lang
                    Name     = $title
                    Codec    = $stream.codec_name
                    Default  = ($stream.disposition.default -eq 1)
                    Forced   = ($stream.disposition.forced -eq 1)
                }
                Write-Log "Субтитры MP4 успешно извлечены: $([IO.Path]::GetFileName($subFile))" -Severity Information -Category 'Subtitles'
            }
            
            $subtitleIndex++
        }
        catch {
            Write-Log "Ошибка при извлечении субтитров MP4 (индекс: $($stream.index)): $_" -Severity Warning -Category 'Subtitles'
            $subtitleIndex++
        }
    }
}

function Convert-MP4ChaptersToXML {
    param([string]$InputFile, [string]$OutputFile)

    try {
        if (-not (Test-Path -LiteralPath $InputFile)) { 
            Write-Log "Файл глав MP4 не найден: $InputFile" -Severity Verbose -Category 'Metadata'
            return 
        }
        
        $content = Get-Content -LiteralPath $InputFile -Raw
        $chapters = [System.Collections.Generic.List[hashtable]]::new()
        
        # Парсим главы из формата FFmetadata
        $lines = $content -split "`n"
        $currentChapter = @{}
        $timeBase = "1/1000"  # значение по умолчанию
        
        foreach ($line in $lines) {
            $line = $line.Trim()
            if ($line -eq '') { continue }
            
            if ($line -match '^\[CHAPTER\]$') {
                if ($currentChapter.Count -gt 0) {
                    $chapters.Add($currentChapter.Clone())
                }
                $currentChapter = @{TimeBase = $timeBase}
            }
            elseif ($line -match '^TIMEBASE=(\d+)/(\d+)$') {
                $timeBase = "$($Matches[1])/$($Matches[2])"
                if ($currentChapter.Count -gt 0) {
                    $currentChapter.TimeBase = $timeBase
                }
            }
            elseif ($line -match '^START=(\d+)$') {
                $currentChapter.Start = [int64]$Matches[1]
            }
            elseif ($line -match '^END=(\d+)$') {
                $currentChapter.End = [int64]$Matches[1]
            }
            elseif ($line -match '^title=(.+)$') {
                $currentChapter.Title = $Matches[1].Trim()
            }
        }
        
        if ($currentChapter.Count -gt 0) {
            $chapters.Add($currentChapter)
        }

        if ($chapters.Count -eq 0) {
            Write-Log "Главы не найдены в файле MP4" -Severity Warning -Category 'Metadata'
            return
        }

        # Создаем XML для mkvmerge
        $settings = [System.Xml.XmlWriterSettings]@{
            Indent = $true
            Encoding = [System.Text.Encoding]::UTF8
        }
        
        $xmlWriter = [System.Xml.XmlWriter]::Create($OutputFile, $settings)
        try {
            $xmlWriter.WriteStartDocument()
            $xmlWriter.WriteDocType("Chapters", "", "matroskachapters.dtd", "")
            $xmlWriter.WriteStartElement("Chapters")
            $xmlWriter.WriteStartElement("EditionEntry")
            
            foreach ($chapter in $chapters) {
                if ($chapter.ContainsKey('Start') -and $chapter.ContainsKey('Title') -and $chapter.ContainsKey('TimeBase')) {
                    # Парсим timebase
                    $timeBaseParts = $chapter.TimeBase -split '/'
                    $numerator = [double]$timeBaseParts[0]
                    $denominator = [double]$timeBaseParts[1]
                    
                    if ($numerator -eq 0) { $numerator = 1 }
                    if ($denominator -eq 0) { $denominator = 1000 }
                    
                    # Конвертируем время из тиков в секунды
                    $startTimeSeconds = $chapter.Start * ($numerator / $denominator)
                    
                    # Форматируем время в формат HH:MM:SS.mmm
                    $timeSpan = [TimeSpan]::FromSeconds($startTimeSeconds)
                    $chapterTime = "{0:00}:{1:00}:{2:00}.{3:000}" -f `
                        [Math]::Floor($timeSpan.TotalHours), 
                        $timeSpan.Minutes, 
                        $timeSpan.Seconds,
                        $timeSpan.Milliseconds
                    
                    $xmlWriter.WriteStartElement("ChapterAtom")
                    
                    # ChapterTimeStart
                    $xmlWriter.WriteStartElement("ChapterTimeStart")
                    $xmlWriter.WriteString($chapterTime)
                    $xmlWriter.WriteEndElement() # ChapterTimeStart
                    
                    # ChapterDisplay
                    $xmlWriter.WriteStartElement("ChapterDisplay")
                    $xmlWriter.WriteElementString("ChapterString", $chapter.Title)
                    $xmlWriter.WriteElementString("ChapterLanguage", "eng")
                    $xmlWriter.WriteEndElement() # ChapterDisplay
                    
                    $xmlWriter.WriteEndElement() # ChapterAtom
                    
                    Write-Log "Глава: $($chapter.Title) - $chapterTime" -Severity Debug -Category 'Metadata'
                }
            }
            
            $xmlWriter.WriteEndElement() # EditionEntry
            $xmlWriter.WriteEndElement() # Chapters
            $xmlWriter.WriteEndDocument()
            
            Write-Log "Успешно сконвертировано $($chapters.Count) глав MP4 в XML" -Severity Information -Category 'Metadata'
        }
        finally {
            $xmlWriter.Close()
        }
    }
    catch {
        Write-Log "Ошибка конвертации глав MP4: $_" -Severity Warning -Category 'Metadata'
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

        $settings = [XmlWriterSettings]@{ Indent = $true; Encoding = [Text.Encoding]::UTF8 }
        $writer = [XmlWriter]::Create($OutputFile, $settings)
        
        try {
            $writer.WriteStartDocument()
            $writer.WriteStartElement("Tags")

            $fields = @{
                TITLE            = $episode.title
                ORIGINAL_TITLE   = $episode.originaltitle
                SUMMARY          = $episode.plot
                DATE_RELEASED    = $episode.premiered
                AIR_DATE         = $episode.aired
                PART_NUMBER      = $episode.episode
                SEASON_NUMBER    = $episode.season
                SHOWTITLE        = $episode.showtitle
            }

            foreach ($field in $fields.GetEnumerator()) {
                if (-not [string]::IsNullOrEmpty($field.Value)) {
                    $writer.WriteStartElement("Tag")
                    $writer.WriteStartElement("Simple")
                    $writer.WriteElementString("Name", $field.Key)
                    $writer.WriteElementString("String", $field.Value)
                    $writer.WriteEndElement()
                    $writer.WriteEndElement()
                }
            }

            foreach ($studio in $episode.studio) {
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", "STUDIO")
                $writer.WriteElementString("String", $studio)
                $writer.WriteEndElement()
                $writer.WriteEndElement()
            }

            foreach ($director in $episode.director) {
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", "DIRECTOR")
                $writer.WriteElementString("String", $director.InnerText)
                $writer.WriteEndElement()
                $writer.WriteEndElement()
            }

            # Добавляем UNIQUEID теги
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
            $fields
        }
        finally {
            $writer.Close()
        }
    }
    catch {
        Write-Log "Ошибка при конвертации NFO в XML: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

Export-ModuleMember -Function Invoke-ProcessMetaData, Complete-MediaFile, `
    Invoke-ProcessMP4Metadata, Convert-MP4ChaptersToXML, ConvertFrom-NfoToXml, `
    Copy-TagsFromSource, Copy-MP4TagsFromSource