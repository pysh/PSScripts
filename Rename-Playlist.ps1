# Rename-Playlist.ps1
. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'
$playlistURL = 'https://vk.com/video/playlist/-209976560_13'
$ArgList = @(
    '--no-warnings'
    '--compat-options manifest-filesize-approx'
    '-J'
    # '-o "[%(upload_date)s] %(title)s.%(ext)s"'
    # '-S "res:1080,vext:mkv,aext:m4a,vcodec:h265"'
    '--'
    ('"{0}"' -f $playlistURL)
) -join ' '
Write-Host 'Collecting information...' -ForegroundColor DarkGray
$retVal = Invoke-Process -commandPath "X:\Apps\_VideoEncoding\ffmpeg\yt-dlp.exe" -commandArguments $ArgList -workingDir "y:\.temp\YT_y\"
$retVal.stdout | Out-File -FilePath 'y:\.temp\YT_y\~files.json' -Encoding utf8 -Append:$false -Force
$j = ConvertFrom-Json $retVal.stdout
Clear-Host
$strCommands = @(); $str = ''; $n=0
$bAudio = $true
$bVideo = $true
foreach ($e in $j.entries) {
    if ($e.requested_downloads.Count -ge 1) {
        $fv = $e.formats |
            Where-Object { (($_.width -ge '1920') -and ($_.protocol -like 'm3u8*')) } | 
            Sort-Object ext, resolution, abr | 
            Select-Object format_id, ext, width, height, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container -Last 1
        
        $fa = $e.formats | 
            Where-Object {$_.acodec -eq 'opus'} | 
            Sort-Object acodec, abr | 
            Select-Object format_id, ext, resolution, fps, filesize, acodec, abr, vbr, tbr -Last 1
        
        
        Write-Host '*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*' -ForegroundColor Magenta
        # Write-Host 'title   :', $e.title -ForegroundColor DarkBlue
        Write-Host 'filename:', $e.requested_downloads[0].filename -ForegroundColor Blue -NoNewline
        Write-Host "`twebpgurl:", $e.webpage_url -ForegroundColor DarkCyan
        $fv | Format-Table -AutoSize
        $fa | Format-Table -AutoSize
        if (($fv.Count -gt 0) -and ($fa.Count -gt 0)) {
            $n++
            if (($fv.Count -gt 1)) {
                Write-Host '>1 formats' -ForegroundColor DarkRed
            }
            $strFormats = @(
                if ($bVideo) {$fv.format_id}
                if ($bVideo -and $bAudio) {'+'}
                if ($bAudio) {$fa.format_id}
            ) -join ''
            $str = @(
                ("# {0}/{1} = {2}" -f $n, $j.entries.count, $e.title)
                ('. yt-dlp.exe --config-locations "X:\Apps\_VideoEncoding\ffmpeg\" --format {0} --proxy "" --paths "temp:R:\\" --paths "y:\.temp\YT_y\Roast Battle+\audio_opus\" -- "{1}"' -f $strFormats, $e.webpage_url)
            )
            $strCommands += '#'
            $strCommands += $str
            Write-Host $str -ForegroundColor DarkYellow -Separator "`r`n"
        }
        else { Write-Host 'NO suitable formats' -ForegroundColor Red }
    }
}
# Write-Host $strCommands -ForegroundColor DarkCyan -Separator "`r`n"
# $strCommands | Out-File -FilePath 'y:\.temp\YT_y\Roast Battle+\audio_opus\get-audio.ps1' -Encoding utf8 -Force