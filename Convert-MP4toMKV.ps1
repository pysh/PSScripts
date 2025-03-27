function Convert-MP4toMKV {
    Param (
        [string]$inPath,
        [array]$filterList = @(".mp4"),
        [string]$outPath = $inPath,
        [string]$extraFilter,
        [string]$coverFile
    )
    # Clear-Host
    foreach ($f in (Get-ChildItem -Path $inPath)) {
        if (($f.Extension -iin $filterList) -and ($f.Name -like $extraFilter)) {
            $outFile = Join-Path -Path $outPath -ChildPath ([IO.Path]::ChangeExtension($f.Name, 'mkv'))
            $prm = @(
                '-hide_banner -loglevel info'
                # ('-y -to 10.000')
                ('-i "{0}"' -f $f)
                ('-map 0:0 -c:V:0 copy')
                '-metadata:s vendor_id=""'
                # ('-map_metadata 0') # Копируем метаданные из Global
                ('-map_chapters 0') # Копируем главы

                #('-map 0:a:0 -c:a:{0} libopus -af:{0} aformat=channel_layouts="7.1|5.1|stereo" -b:a:{0} 384k -disposition:{0} default -metadata:s:a:0 handler_name="[Кубик в Кубе | Opus 5.1 Audio]"' -f '0')
                ('-map 0:a:0 -c:a:{0} copy -disposition:{0} default -metadata:s:a:0 handler_name="[Кубик в Кубе | Opus 5.1 Audio]"' -f '0')
                ('-map 0:s -c:s srt -disposition:s 0 -disposition:s:0 default')

                # Добавление ковра
                if ($coverFile -notin ($null, '')) {
                    ('-attach "{0}"' -f $coverFile)
                    ('-metadata:s:t:0 mimetype=image/jpeg')
                    ('-metadata:s:t:0 filename=cover.jpg')
                }
                # '-bsf:v "filter_units=remove_types=6"'
                # '-bsf:v "filter_units=remove_types=39"'
                # '-fflags +bitexact -flags:v +bitexact -flags:a +bitexact -flags:s +bitexact'
                ('"{0}"' -f $outFile)
            )
            Write-Host $f -ForegroundColor Cyan
            Write-Host $outFile -ForegroundColor DarkCyan
            Write-Host $outFile ($prm -join ' ') -ForegroundColor Blue
            Start-Process -FilePath 'ffmpeg.exe' -ArgumentList ($prm -join ' ') -Wait -NoNewWindow
            Write-Host ''
        }
    }
}
Clear-Host
Convert-MP4toMKV -inPath 'y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\' `
    -filterList @('.mp4') `
    -outPath 'k:\temp\Boys\season 01\' `
    -extraFilter '*' `
    -coverFile 'y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2020.S02.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\mkv\cover.png'

    <#
"X:\Apps\_VideoEncoding\ffmpeg\ffmpeg.EXE"
-y
-i "y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8.mp4"
-metadata title="The Boys S01E01. The Name of the Game"
-max_muxing_queue_size 1024
-map 0:0
    -c:v copy
    -pix_fmt yuv420p10le
-map_metadata 0
-map_chapters 0
-map 0:1
    -metadata:s:1 title="[Кубик в Кубе | Opus 5.1 Audio]"
    -metadata:s:1 handler="[Кубик в Кубе | Opus 5.1 Audio]"
    -metadata:s:1 language=rus
    -c:1 libopus
    -b:1 384k
    -filter:1 aformat=channel_layouts="5.1(side)"
    -ac:1 6
    -filter:1 aformat=channel_layouts=5.1(side)
    -disposition:1 default
    -strict -2
-map 0:7
    -c:2 copy
    -disposition:2 default
    -metadata:s:2 language='rus'
-map 0:8
    -c:3 copy
    -disposition:3 0
    -metadata:s:3 language='eng'
-attach "Y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\cover.jpg"
    -metadata:s:0 mimetype="image/jpeg"
    -metadata:s:0  filename="cover.jpg"
"y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8-fastflix-4a91.mkv"
#>