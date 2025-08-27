<#
.SYNOPSIS
    Модуль для обработки метаданных мультимедиа
#>

using namespace System.Xml
using namespace System.Text

function Invoke-ProcessMetaData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    try {
        Write-Log "Начало обработки метаданных" -Severity Information -Category 'Metadata'
        
        $metadataDir = Join-Path -Path $Job.WorkingDir -ChildPath "meta"
        New-Item -ItemType Directory -Path $metadataDir -Force -ErrorAction Stop | Out-Null
        $Job.Metadata = @{ 
            TempDir = $metadataDir
            Attachments = [System.Collections.Generic.List[object]]::new()
        }
        Write-Log "Создана временная директория для метаданных: $metadataDir" -Severity Verbose -Category 'Metadata'

        $originalEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        $jsonInfo = & $global:VideoTools.MkvMerge -J $Job.VideoPath | ConvertFrom-Json
        [Console]::OutputEncoding = $originalEncoding

        Write-Log "Получена информация о медиафайле в JSON" -Severity Debug -Category 'Metadata'

        Invoke-ProcessAttachments -jsonInfo $jsonInfo -Job $Job -metadataDir $metadataDir
        Invoke-ProcessSubtitles -jsonInfo $jsonInfo -Job $Job -metadataDir $metadataDir

        # Извлечение глав и тегов
        $tagsFile = Join-Path -Path $metadataDir -ChildPath "$($Job.BaseName)_tags.xml"
        $chaptersFile = Join-Path -Path $metadataDir -ChildPath "$($Job.BaseName)_chapters.xml"
        
        & $global:VideoTools.MkvExtract $Job.VideoPath tags $tagsFile *>$null
        & $global:VideoTools.MkvExtract $Job.VideoPath chapters $chaptersFile *>$null

        # Обработка NFO файла
        $nfoFile = [IO.Path]::ChangeExtension($Job.VideoPath, "nfo")
        if (Test-Path -LiteralPath $nfoFile -PathType Leaf) {
            $nfoTagsFile = Join-Path -Path $Job.WorkingDir -ChildPath "$($Job.BaseName)_nfo_tags.xml"
            $fields = ConvertFrom-NfoToXml -NfoFile $nfoFile -OutputFile $nfoTagsFile
            $Job.NFOFields = $fields
            $Job.NfoTags = $nfoTagsFile
            $Job.TempFiles.Add($nfoTagsFile)
            Write-Log "Конвертирован NFO файл в XML: $nfoTagsFile" -Severity Information -Category 'Metadata'
        }

        $Job.TempFiles.Add($metadataDir)
        Write-Log "Обработка метаданных завершена успешно" -Severity Success -Category 'Metadata'
        return $Job
    }
    catch {
        Write-Log "Критическая ошибка при обработке метаданных: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

function Complete-MediaFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    try {
        Write-Log "Начало создания итогового файла" -Severity Information -Category 'Muxing'
        
        $mkvArgs = @(
            '--ui-language', 'en',
            '--priority', 'lower',
            '--output', $Job.FinalOutput,
            '--no-date', $Job.VideoOutput,
            '--no-track-tags'
        )

        # Аудиодорожки
        foreach ($audioTrack in $Job.AudioOutputs) {
            $mkvArgs += @(
                '--language', "0:$($audioTrack.Language)",
                $(if ($audioTrack.Title) { @('--track-name', "0:$($audioTrack.Title)") }),
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

        # Теги
        $tagsFile = if ($Job.NfoTags) { $Job.NfoTags } else { Join-Path -Path $Job.Metadata.TempDir -ChildPath "$($Job.BaseName)_tags.xml" }
        if (Test-Path -LiteralPath $tagsFile -PathType Leaf) {
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
                    $attachArgs += '--attachment-description'
                    $attachArgs += $attach.Description
                }
                
                & $global:VideoTools.MkvPropedit @attachArgs
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
    param (
        [object]$jsonInfo,
        [hashtable]$Job,
        [string]$metadataDir
    )

    foreach ($attachment in $jsonInfo.attachments) {
        try {
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

function Invoke-ProcessSubtitles {
    param (
        [object]$jsonInfo,
        [hashtable]$Job,
        [string]$metadataDir
    )

    foreach ($track in $jsonInfo.tracks | Where-Object { $_.type -eq 'subtitles' }) {
        try {
            $lang = if ($track.properties.language -eq 'und') { '' } else { $track.properties.language }
            $ext = switch ($track.codec) {
                'SubStationAlpha' { 'ass' }
                'HDMV PGS'       { 'sup' }
                'VobSub'         { 'sub' }
                default          { 'srt' }
            }

            $subFile = Join-Path -Path $metadataDir -ChildPath (
                "sID{0}_[{1}]_{{`{2`}}}{3}{4}.{5}" -f 
                $track.id,
                $lang,
                $track.properties.track_name,
                ($track.properties.default_track ? '+' : '-'),
                ($track.properties.forced_track ? 'F' : ''),
                $ext
            )
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
                Write-Log "Субтитры успешно извлечены: $subFile" -Severity Debug -Category 'Subtitles'
            }
        }
        catch {
            Write-Log "Не удалось извлечь субтитры (трек $($track.id)): $_" -Severity Warning -Category 'Subtitles'
        }
    }
}

function ConvertFrom-NfoToXml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$NfoFile,
        
        [Parameter(Mandatory)]
        [string]$OutputFile
    )

    try {
        [xml]$nfoContent = Get-Content -LiteralPath $NfoFile -ErrorAction Stop
        $episode = $nfoContent.episodedetails

        $settings = [XmlWriterSettings]@{
            Indent = $true
            Encoding = [Text.Encoding]::UTF8
        }

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
                    $writer.WriteEndElement() # Simple
                    $writer.WriteEndElement() # Tag
                }
            }

            # Студии
            foreach ($studio in $episode.studio) {
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", "STUDIO")
                $writer.WriteElementString("String", $studio)
                $writer.WriteEndElement() # Simple
                $writer.WriteEndElement() # Tag
            }

            # Люди
            foreach ($director in $episode.director) {
                $writer.WriteStartElement("Tag")
                $writer.WriteStartElement("Simple")
                $writer.WriteElementString("Name", "DIRECTOR")
                $writer.WriteElementString("String", $director.InnerText)
                $writer.WriteEndElement() # Simple
                $writer.WriteEndElement() # Tag
            }

            $writer.WriteEndElement() # Tags
            $writer.WriteEndDocument()
            $fields
        }
        finally {
            $writer.Close()
        }
        
        Write-Log "Успешно конвертирован NFO в XML: $OutputFile" -Severity Information -Category 'Metadata'
    }
    catch {
        Write-Log "Ошибка при конвертации NFO в XML: $_" -Severity Error -Category 'Metadata'
        throw
    }
}

Export-ModuleMember -Function Invoke-ProcessMetaData, Complete-MediaFile