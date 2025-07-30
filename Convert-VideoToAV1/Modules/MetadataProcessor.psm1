<#
.SYNOPSIS
    Enhanced metadata processor with complete subtitle and attachment support
#>

using namespace System.Xml
using namespace System.Text

function Process-Metadata {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    # Create temp directory with timestamp
    $metadataDir = Join-Path -Path $Job.WorkingDir -ChildPath "meta"
    New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
    $Job.Metadata = @{ TempDir = $metadataDir }

    # 1. Get complete file info as JSON
    $originalEncoding = [Console]::OutputEncoding
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $jsonInfo = & $global:VideoTools.MkvMerge -J $Job.VideoPath | ConvertFrom-Json
    [Console]::OutputEncoding = $originalEncoding

    # 2. Process attachments
    $attachmentFiles = @()
    foreach ($attachment in $jsonInfo.attachments) {
        try {
            $safeName = [IO.Path]::GetFileName($attachment.file_name) -replace '[^\w\.-]', '_'
            $outputFile = Join-Path -Path $metadataDir -ChildPath "attach_$($attachment.id)_$safeName"
            
            # & $global:VideoTools.MkvExtract $Job.VideoPath attachments $($attachment.id):$outputFile *>$null
            
            $mkvExtractParams = @($Job.VideoPath, "attachments", "$($attachment.id):`"${outputFile}`"")
            Start-Process -FilePath $global:VideoTools.MkvExtract -ArgumentList $mkvExtractParams -NoNewWindow -Wait -WorkingDirectory $Job.WorkingDir

            if (Test-Path -LiteralPath $outputFile) {
                $attachmentFiles += @{
                    Path = $outputFile
                    Name = $attachment.file_name
                    Mime = $attachment.content_type
                    Description = $attachment.description
                }
            }
        }
        catch {
            Write-Warning "Attachment $($attachment.id) extraction failed: $_"
        }
    }
    $Job.Metadata['Attachments'] = $attachmentFiles

    # 3. Process subtitles with full metadata
    foreach ($track in $jsonInfo.tracks | Where-Object { $_.type -eq 'subtitles' }) {
        try {
            $lang = $track.properties.language -eq 'und' ? '' : $track.properties.language
            $ext = switch ($track.codec) {
                'SubStationAlpha' { 'ass' }
                'HDMV PGS'       { 'sup' }
                'VobSub'         { 'sub' }
                default          { 'srt' }
            }
            
            $subFile = Join-Path -Path $metadataDir "sub_$($track.id)_$(if($lang){$lang+"_"})$(Get-SafeName $track.properties.track_name).$ext"
            
            $mkvExtractParams = @($Job.VideoPath, "tracks", "$($track.id):`"${subFile}`"")
            Start-Process -FilePath $global:VideoTools.MkvExtract -ArgumentList $mkvExtractParams -NoNewWindow -Wait -WorkingDirectory $Job.WorkingDir

            # & $global:VideoTools.MkvExtract $Job.VideoPath tracks $($track.id):$subFile *>$null
            
            if (Test-Path -LiteralPath $subFile) {
                $Job.Metadata["Subtitle_$($track.id)"] = @{
                    Path = $subFile
                    Language = $lang
                    Name = $track.properties.track_name
                    Codec = $track.codec
                }
            }
        }
        catch {
            Write-Warning "Subtitle track $($track.id) extraction failed: $_"
        }
    }

    # 4. Extract other metadata
    & $global:VideoTools.MkvExtract $Job.VideoPath tags (Join-Path -Path $metadataDir "tags.xml")
    & $global:VideoTools.MkvExtract $Job.VideoPath chapters (Join-Path -Path $metadataDir "chapters.xml")

    # 5. Process NFO if exists
    $nfoFile = [IO.Path]::ChangeExtension($Job.VideoPath, "nfo")
    if (Test-Path -LiteralPath $nfoFile) {
        $nfoTagsFile = Join-Path -Path $Job.WorkingDir "$($Job.BaseName)_nfo_tags.xml"
        Create-TagsFromNfo -NfoFile $nfoFile -OutputFile $nfoTagsFile
        $Job.NfoTags = $nfoTagsFile
        $Job.TempFiles += $nfoTagsFile
    }

    $Job.TempFiles += $metadataDir
    return $Job
}

function Complete-Conversion {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Job
    )

    $Job.FinalOutput = Join-Path -Path $Job.WorkingDir "$($Job.BaseName)_out.mkv"
    
    # Prepare mkvmerge arguments
    $mkvArgs = @(
        '--output', $Job.FinalOutput
        '--no-date' # Prevent date modification
        $Job.VideoOutput
    ) + $Job.AudioOutputs

    # Add subtitles with metadata
    $Job.Metadata.GetEnumerator() | Where-Object { $_.Key -match "^Subtitle_\d+" } | Sort-Object {$_.Key} | ForEach-Object {
        $sub = $_.Value
        $mkvArgs += "--language", "0:$($sub.Language)"
        if ($sub.Name) {
            $mkvArgs += "--track-name", "0:$($sub.Name)"
        }
        $mkvArgs += $sub.Path
    }

    # Add chapters
    $chaptersFile = Join-Path -Path $Job.Metadata.TempDir "chapters.xml"
    if (Test-Path -LiteralPath $chaptersFile) {
        $mkvArgs += '--chapters', $chaptersFile
    }

    # Add global tags
    $tagsFile = if ($Job.NfoTags) { $Job.NfoTags } else { Join-Path -Path $Job.Metadata.TempDir "tags.xml" }
    if (Test-Path -LiteralPath $tagsFile) {
        $mkvArgs += '--global-tags', $tagsFile
    }

    # Execute mkvmerge
    & $global:VideoTools.MkvMerge @mkvArgs

    # Add attachments with full metadata
    foreach ($attach in $Job.Metadata['Attachments']) {
        if (Test-Path -LiteralPath $attach.Path) {
            $attachArgs = @(
                '--attachment-name', $attach.Name
                '--attachment-mime-type', $attach.Mime
                '--add-attachment', $attach.Path
            )
            if ($attach.Description) {
                $attachArgs += '--attachment-description', $attach.Description
            }
            & $global:VideoTools.MkvPropedit $Job.FinalOutput @attachArgs
        }
    }
}

function Get-SafeName {
    param([string]$name)
    return [RegEx]::Replace($name, '[^\w\- ]', '').Trim() -replace '\s+', '_'
}

function Create-TagsFromNfo {
    param(
        [Parameter(Mandatory)]
        [string]$NfoFile,
        
        [Parameter(Mandatory)]
        [string]$OutputFile
    )

    [xml]$nfoContent = Get-Content -LiteralPath $NfoFile
    $episode = $nfoContent.episodedetails

    $settings = [XmlWriterSettings]@{
        Indent = $true
        Encoding = [Text.Encoding]::UTF8
    }

    $writer = [XmlWriter]::Create($OutputFile, $settings)
    try {
        $writer.WriteStartDocument()
        $writer.WriteStartElement("Tags")

        # Standard fields
        $fields = @{
            "TITLE" = $episode.title
            "ORIGINAL_TITLE" = $episode.originaltitle
            "SUMMARY" = $episode.plot
            "DATE_RELEASED" = $episode.premiered
            "AIR_DATE" = $episode.aired
            "PART_NUMBER" = $episode.episode
            "SEASON_NUMBER" = $episode.season
            "SHOWTITLE" = $episode.showtitle
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

        # Studios
        foreach ($studio in $episode.studio) {
            $writer.WriteStartElement("Tag")
            $writer.WriteStartElement("Simple")
            $writer.WriteElementString("Name", "STUDIO")
            $writer.WriteElementString("String", $studio)
            $writer.WriteEndElement() # Simple
            $writer.WriteEndElement() # Tag
        }

        # People
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
    }
    finally {
        $writer.Close()
    }
}

Export-ModuleMember -Function Process-Metadata, Complete-Conversion