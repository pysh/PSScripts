Clear-Host
$filterList = @(".mkv", ".m2ts")
$files = Get-ChildItem -LiteralPath 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 05\' |
Where-Object { ($_.Extension -iin $filterList) }
$ffmpeg_nonfree = 'd:\Sources\media-autobuild_suite\local64\bin-video\ffmpeg.exe'
$titleRegexp = '^(?<title>.*\[\d{4}-\d{2}-\d{2}\])\[.*$'

function Get-AudioTrackDetails {
    param ([string]$FilePath)

    try {
        $trackInfo = & ffprobe -v quiet -print_format json -show_streams -select_streams a "$FilePath"
        $audioStreams = $trackInfo | ConvertFrom-Json

        return $audioStreams.streams | ForEach-Object {
            [PSCustomObject]@{
                Index    = $_.index
                Codec    = $_.codec_name
                Channels = $_.channels
                Language = $_.tags.language ?? "und"
                BitRate  = $_.bit_rate
                Title    = $_.tags.title ?? "Unknown Track"
            }
        }
    }
    catch {
        Write-EncodingLog -Message "Failed to extract audio track details" -Level "Error"
        return $null
    }
}

foreach ($f in $files) {
    $audio_tracks = Get-AudioTrackDetails -FilePath $f.FullName
    $out_file = ('"{0}_[audio].mka"' -f $f.FullName).Replace('[1080p][AVC].m2ts_', '')
    $cover_file = 'y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 05\cover.jpg'
    $enc_options_0ch = 'copy'
    $enc_options_2ch = 'libfdk_aac -vbr 5'
    $enc_options_6ch = 'libfdk_aac -vbr 4'
    $enc_options_8ch = 'libfdk_aac -vbr 4'
    
    if ($f.BaseName -match $titleRegexp) {
        $title = $Matches.title
    }
    else {
        $title = ""
    }

    if (-not (Test-Path -LiteralPath $out_file)) {
        $prm = @(
            '-y -hide_banner'
            ('-i "{0}"' -f $f.FullName)
            # '-map_metadata 0 -vn -dn -map 0 -map -0:a -c libopus -map 0:a'
            '-map_metadata 0', '-vn', '-dn'
            '-metadata:s vendor_id=""'

            # Add Title
            ('-metadata title="{0}"' -f $title)
            # TWD s05
            ('-map 0:a:{0} -c:a:{0} {1} -disposition:{0} 0 -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | 7.1 AAC Audio]" -metadata:s:a:{0} encoder=""' -f '0', $enc_options_8ch)
            ('-map 0:a:{0} -c:a:{0} {1} -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[FoxCrime | 7.1 AAC Audio]" -metadata:s:a:{0} encoder=""' -f '1', $enc_options_8ch)
            ('-map 0:a:{0} -c:a:{0} {1} -disposition:{0} default -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | 7.1 AAC Audio]" -metadata:s:a:{0} encoder=""' -f '2', $enc_options_8ch)
            ('-map 0:a:{0} -c:a:{0} {1} -disposition:{0} 0 -metadata:s:a:{0} language=uk -metadata:s:a:{0} title="[UATEAM | 7.1 AAC Audio]" -metadata:s:a:{0} encoder=""' -f '3', $enc_options_8ch)
            if ($audio_tracks.count -eq 5) {
            ('-map 0:a:{0} -c:a:{0} {1} -ac:{0} 2 -disposition:{0} comment -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Comment | AC3 2.0 Audio]" -metadata:s:a:{0} encoder=""' -f '4', $enc_options_0ch)
                # Map subtitles
                '-map 0:s:0  -c:s copy -metadata:s:5 language=eng'
                '-map 0:s:1  -c:s copy -metadata:s:6 language=rus'
            }
            elseif ($audio_tracks.count -eq 6) {
                ('-map 0:a:{0} -c:a:{0} {1} -ac:{0} 2 -disposition:{0} comment -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Comment | AC3 2.0 Audio]" -metadata:s:a:{0} encoder=""' -f '4', $enc_options_0ch)
                ('-map 0:a:{0} -c:a:{0} {1} -ac:{0} 2 -disposition:{0} comment -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Comment | AC3 2.0 Audio]" -metadata:s:a:{0} encoder=""' -f '5', $enc_options_0ch)
                # Map subtitles
                '-map 0:s:0  -c:s copy -metadata:s:6 language=eng'
                '-map 0:s:1  -c:s copy -metadata:s:7 language=rus'    
            }
            else {
                # Map subtitles
                '-map 0:s:0  -c:s copy -metadata:s:4 language=eng'
                '-map 0:s:1  -c:s copy -metadata:s:5 language=rus'
            }
            # # Attach cover
            if ($cover_file -notin ($null, '')) {
                ('-attach "{0}"' -f $cover_file)
                ('-metadata:s:t:0 mimetype=image/jpeg')
                ('-metadata:s:t:0 filename=cover.jpg')
            }
            $out_file
        )
        Write-Host "`r`n" + ($prm -join ' ') -ForegroundColor DarkCyan
        Start-Process -FilePath $ffmpeg_nonfree -ArgumentList ($prm -join ' ') -Wait -NoNewWindow
    }
    else {
        Write-Host "Output file already exists: $out_file" -ForegroundColor Magenta
    }
}
<#region OLDPRESETS
        # Boys 02
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Кубик в Кубе | Opus 5.1 Audio]"' -f '0')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[AlexFilm | Opus 5.1 Audio]"' -f '1')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[HDRezka Studio | Opus 5.1 Audio]"' -f '2')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | Opus 5.1 Audio]"' -f '3')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[TVShows | Opus 5.1 Audio]"' -f '4')
        ('-map 0:a:{0} -c:a:{0} copy -disposition:{0} default -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | EAC3 5.1 Audio]"' -f '5')
        ('"{0}_[audio].mka"' -f $f.FullName)
        # Boys 01
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Кубик в Кубе | Opus 5.1 Audio]"' -f '0')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[AlexFilm | Opus 5.1 Audio]"' -f '1')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 192k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[HDRezka Studio | Opus 2.0 Audio]"' -f '2')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | Opus 5.1 Audio]"' -f '3')
        ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 384k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[TVShows | Opus 5.1 Audio]"' -f '4')
        ('-map 0:a:{0} -c:a:{0} copy -disposition:{0} 0 -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | EAC3 5.1 Audio]"' -f '5')
        ('"{0}_[audio].mka"' -f $f.FullName)
        # # Bear s03
        #         ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} default -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[HDRezka Studio | Opus 5.1 Audio]"' -f '1')
        #         ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | Opus 2.0 Audio]"' -f '2')
        #         ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[TVShows | Opus 5.1 Audio]"' -f '0')
        #         ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | Opus 5.1 Audio]"' -f '3')
        #         ('"{0}_[audio].mka"' -f $f.FullName)
#>
