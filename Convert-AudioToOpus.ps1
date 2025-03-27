Param (
    [System.String]$filePath = ('
    g:\Видео\Сериалы\Зарубежные\Чёрное зеркало (Black Mirror)\Black.Mirror.S06.WEBDL.2160p.Rus.Eng\audio_tracks\
        ').Trim()
)
[datetime]$dtFrom = Get-Date
[string]$ffmpeg = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
[string]$opusenc = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe'
[string]$qaac = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe'

. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'

# $filterList= @(".mp2", ".mp3", ".mpa", ".ogg", ".opus", ".dts", ".dtshd", ".ac3", ".eac3", ".thd", ".wav")
# $filterList = @(".dts", ".ac3", ".eac3", ".aac") #, ".opus")
$filterList = @('.ac3', '.eac3', '.aac')
$extraFilter = "*"


Clear-Host
$filePath = (Get-Item -LiteralPath $filePath).FullName

$files = Get-ChildItem -LiteralPath $filePath -File -Recurse |
Where-Object {
            ($_.Extension -iin $filterList) -and
            ($_.BaseName -like $extraFilter)
}
Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen
$TotalFiles = $files.Count
$ProcessedFiles = 0

$files | Foreach-Object -ThrottleLimit 4 -Parallel {
    $proc = $using::ProcessedFiles
    [bool]$runAsPipe = $false
    [string]$ffmpeg = 'X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.exe'
    [string]$opusenc = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe'
    [string]$strChannels    = ''
    [string]$track_language = ''
    [string]$track_title    = ''
    . 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1'
    $inFile = $_
    $audioChannels = Get-AudioTrackChannels -AudioFilePath $inFile.FullName
    $outFlacFile = [IO.Path]::ChangeExtension($inFile, 'flac')
    $outOpusFile = [IO.Path]::ChangeExtension($inFile, 'opus')
    $bitRate = 256; $strChannels = ''
    switch ($audioChannels) {
        2 { $bitRate = 160; $strChannels = '2.0' }
        6 { $bitRate = 320; $strChannels = '5.1' }
        8 { $bitRate = 384; $strChannels = '7.1' } 
        Default { $bitRate = 160; $strChannels = '2.0' }
    }

    # Get language of file
    if ($inFile.BaseName -match '^.*\[(?<track_language>\D{2,3})\].*$') {
        if ($Matches.Count -ge 1) {
            $track_language = $Matches.track_language
        }
    }

    if ($inFile.BaseName -match '^.*{(?<track_title>.*)}.*') {
        if ($Matches.Count -ge 1) {
            [string]$track_title = $Matches.track_title
            if ($track_title -like '`[*`]') {
                $track_title = $track_title.Replace('AC3', 'Opus')
                $track_title = $track_title.Replace('dts', 'Opus')
                $track_title = $track_title.Replace(' _ ', ' | ')
            }
            else {
                $track_title = switch -Regex ($track_title) {
                    'NS'  { 'NewStudio' }
                    'LF'  { 'LostFilm' }
                    'HDr' { 'HDRezka' }
                    'En[g]'  { 'Original' }
                }
                $track_title = "[${track_title} | ${strChannels} Opus]"
            }
        }
    }

    if ($runAsPipe) {
        #Write-Host $inFile -ForegroundColor DarkYellow
        . "$ffmpeg" -i "$inFile" -f flac - | opusenc --vbr --bitrate $bitRate --title "$track_title" - "$outOpusFile" | Out-Null
        # . "$ffmpeg" -i "$inFile" -acodec pcm_s16le -f wav - | opusenc --vbr --bitrate $bitRate --title "$track_title" - "$outOpusFile" | Out-Null
        #Write-Host $inFile -ForegroundColor DarkGreen
    }
    else {
        $argsFlac = @(
            "-y", "-hide_banner"
            ('-i "{0}"' -f $inFile)
            '-f flac'
            ('"{0}"' -f $outFlacFile)
        )
        $argsOpus = @(
            # ('--discard-comments')
            ('--vbr --bitrate {0}' -f $bitRate)
            # ('--title "{0}"' -f $track_title)
            ("--comment title=`"${track_title}`"")
            ("--comment language=${track_language}")
            ('"{0}"' -f $outFlacFile)
            ('"{0}"' -f $outOpusFile)
        )

        Write-Host "Start: ${inFile}`r`nTitle: ${track_title}`tLanguage: ${track_language}" -ForegroundColor DarkYellow
        Start-Process -Path $ffmpeg -ArgumentList $argsFlac -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
        Start-Process -Path $opusenc -ArgumentList $argsOpus -Wait -NoNewWindow -RedirectStandardError "NUL" | Out-Null
    
    }

    # Delete temp flac file
    if (Test-Path -LiteralPath $outFlacFile) { Remove-Item -LiteralPath $outFlacFile -Force }

    # Write status for converted file
    if (Test-Path -LiteralPath $outOpusFile) {
        $proc++
        Write-Debug $proc -Debug
        # $using::ProcessedFiles++
        # Write-Host "(${$using::ProcessedFiles}/{$using::TotalFiles}): ${outOpusFile}" -ForegroundColor DarkGreen
    }
    else {
        # Write-Host "Error: ${outFlacFile}" -ForegroundColor DarkMagenta
    }

}

Write-Host ("Выполнено за {0}" -f ($(Get-Date) - $dtFrom)) -ForegroundColor Blue