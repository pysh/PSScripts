Clear-Host
$filterList = @(".mkv")
$files = Get-ChildItem -LiteralPath 'f:\Видео\Сериалы\Зарубежные\Бункер (Укрытие) (Silo)\Silo.S01.WEB-DL.2160p.H265.10bit.SDR\' |
Where-Object { ($_.Extension -iin $filterList) }
foreach ($f in $files) {
    $prm = @(
        '-y -hide_banner -loglevel error'
        ('-i "{0}"' -f $f.FullName)
        '-map_metadata 0 -vn -dn -map 0 -map -0:a -c copy -map 0:a'
        '-c:a:0 libopus -af:0 aformat=channel_layouts="7.1|5.1|stereo" -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=ru -metadata:s:a:0 title="[Невафильм DUB | Opus 5.1 Audio]"'
        '-c:a:1 libopus -b:a:1 160k -ac:1 2 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title="[LostFilm MVO | Opus 2.0 Audio]"'
        '-c:a:2 libopus -af:2 aformat=channel_layouts="7.1|5.1|stereo" -b:a:2 320k -ac:2 6 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title="[HDRezka MVO | Opus 5.1 Audio]"'
        '-c:a:3 libopus -b:a:3 160k -ac:3 2 -disposition:3 0 -metadata:s:a:3 language=ru -metadata:s:a:3 title="[TVShows MVO | Opus 2.0 Audio]"'
        '-c:a:4 libopus -af:4 aformat=channel_layouts="7.1|5.1|stereo" -b:a:4 320k -ac:4 6 -disposition:4 0 -metadata:s:a:4 language=en -metadata:s:a:4 title="[Original | Opus 5.1 Audio]"'
        ('"{0}_[audio].mkv"' -f $f.FullName)
    )
    Start-Process -FilePath 'ffmpeg.exe' -ArgumentList ($prm -join ' ') -Wait -NoNewWindow
}