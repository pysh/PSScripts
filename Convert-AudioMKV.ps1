Clear-Host
$filterList = @(".mkv")
$files = Get-ChildItem -LiteralPath 'y:\Видео\Сериалы\Зарубежные\22.11.1963\8888888\' |
Where-Object { ($_.Extension -iin $filterList) }
. .\Ge
foreach ($f in $files) {
    $tracks = @()
    0..9 | ForEach-Object ($_) {         Write-Host $_     }
    $prm = @(
        '-y -hide_banner -loglevel error'
        ('-i "{0}"' -f $f.FullName)

        # '-map_metadata 0 -vn -dn -map 0 -map -0:a -c libopus -map 0:a'
        '-map_metadata 0', '-map 0', '-c copy', '-vn', '-dn'

        ('-c:a:{0} libopus -b:a:{0} 130k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Кубик в Кубе | Opus 2.0 Audio]"' -f '0')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[AlexFilm | Opus 2.0 Audio]"' -f '1')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[FocusStudio | Opus 2.0 Audio]"' -f '2')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Jaskier | Opus 2.0 Audio]"' -f '3')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | Opus 2.0 Audio]"' -f '4')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[NewStudio | Opus 2.0 Audio]"' -f '5')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Original | Opus 2.0 Audio]"' -f '6')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[Original | Opus 5.1 Audio]"' -f '7')

        <#
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - HDRezka Studio | Opus 2.0 Audio]"' -f '0')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - HDRezka Studio 18+ | Opus 2.0 Audio]"' -f '1')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - Jaskier | Opus 5.1 Audio]"' -f '2')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - LostFilm | Opus 2.0 Audio]"' -f '3')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - TVShows | Opus 5.1 Audio]"' -f '4')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} default -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[DVO - Кубик в Кубе | Opus 2.0 Audio]"' -f '5')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[MVO - NewComers | Opus 5.1 Audio]"' -f '6')
        ('-c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[DUB - Red Head Sound | Opus 2.0 Audio]"' -f '7')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[DVO - ViruseProject | Opus 5.1 Audio]"' -f '8')
        ('-c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | Opus 5.1 Audio]"' -f '9')
#>
        ('"{0}_[audio].mkv"' -f $f.FullName)
    )

    Write-Host "`r`n" + ($prm -join ' ') -ForegroundColor DarkCyan

    Start-Process -FilePath 'ffmpeg.exe' -ArgumentList ($prm -join ' ') -Wait -NoNewWindow
}