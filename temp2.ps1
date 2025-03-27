Add-Type -Path 'c:\Users\pauln\OneDrive\Documents\PowerShell\Modules\Get-MediaInfo\3.7\MediaInfoSharp.dll'
$mi = New-Object MediaInfoSharp -ArgumentList 'y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8.mp4'
$mi


$x = 5
switch ($x) {
    { $_ -in (1, 5) } { '1, 5' }
    (2) { '2' }
    Default { '0' }
}


Function Get-TagsFromMKV ([string]$Path = 'y:\.temp\YT_y\БЫЛОСЛОВО\', [string]$extraFilter = '*', $filterList = @('.mkv')) {
    Clear-Host
    $InputFileList = Get-ChildItem -LiteralPath $Path -File:$true | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -like $extraFilter)) }
    Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue
    $fileListInfo = @(@())
    foreach ($fileIn in $InputFileList) {
        # $fileIn = 'y:\.temp\YT_y\БЫЛОСЛОВО\БЫЛОСЛОВО. #1. Зоя Яровицына. Александр Якушев. Денис Гвоздев. Игорь Джабраилов [-218471730_456239089].mkv'
        $fileFrames = $fileIn.FullName + '_frames.json'
        $fileInfo = $fileIn.FullName + '_info.json'
        
        Write-Host 'Scanning Info...' -ForegroundColor DarkMagenta
        $prm = ('-hide_banner -loglevel error -select_streams v:0 -show_format -show_streams -print_format json -i "{0}" -o "{1}"' -f $fileIn.FullName, $fileInfo)
        Start-Process -FilePath 'ffprobe.exe' -ArgumentList $prm -NoNewWindow -Wait

        if (Test-Path -Path ([WildcardPattern]::Escape($fileInfo)) -PathType Leaf) {
            Write-Host 'Parsing Info...' -ForegroundColor DarkMagenta
            $info = Get-Content -Path ([WildcardPattern]::Escape($fileInfo)) | ConvertFrom-Json
            Remove-Item -Path ([WildcardPattern]::Escape($fileInfo))
            
            #Write-Host $info.format -ForegroundColor DarkGreen | ConvertTo-Json #'frames count: {0}' -f $frames.frames.Count)
            #Write-Host $info.streams -ForegroundColor DarkCyan #'frames count: {0}' -f $frames.frames.Count)
            #$info.format.tags | Format-List
            # $fileNameNew = $fileIn.FullName.Replace('\БЫЛОСЛОВО.', ('\БЫЛОСЛОВО - {0} - ' -f $info.format.tags.DATE))
            # $fileListInfo += @([PSCustomObject]@{
            #         filename    = $info.format.filename;
            #         date        = $info.format.tags.DATE;
            #         filenamenew = $fileNameNew
            #     });
            #Rename-Item -Path ([WildcardPattern]::Escape($fileIn)) -NewName $fileNameNew
        }
        else {
            Write-Host ("File not found: {0}" -f $fileInfo) -ForegroundColor Magenta
        }
        
        if (Test-Path $fileFrames -PathType Leaf) {
            Remove-Item -Path ([WildcardPattern]::Escape($fileFrames))
        }
    }
    $fileListInfo | Out-File -FilePath (Join-Path $Path -ChildPath list.txt)
    $fileListInfo | ConvertTo-Json | Out-File -FilePath (Join-Path $Path -ChildPath list.json)
    $fileListInfo | ConvertTo-Xml | Out-File -FilePath (Join-Path $Path -ChildPath list.xml)
}
Get-TagsFromMKV -Path 'y:\.temp\YT_y\БЫЛОСЛОВО\'  


<#
title             
PURL              
creation_time     
COMMENT           
ARTIST            
DATE              
DESCRIPTION       
SYNOPSIS          
ENCODER           
"C:\Program Files\MKVToolNix\mkvmerge.exe"
    --ui-language en
    --priority lower
    --output ^"Y:\.temp\YT_y\Стендап комики 4k\out_[SvtAv1EncApp]\Дмитрий Дедков - Одинёшенька ^(Стендап коцерт, 2022^)[4k][av1].mkv^"
    --no-attachments
    --language 0:ru
    --display-dimensions 0:3840x2160
    --language 1:ru ^"^(^" ^"Y:\.temp\YT_y\Стендап комики 4k\out_[SvtAv1EncApp]\Дмитрий Дедков - Одинёшенька ^(Стендап коцерт, 2022^)_[SvtAv1EncApp].mkv^" ^"^)^"
    --no-audio
    --no-video
    --no-track-tags ^"^(^" ^"y:\.temp\YT_y\Стендап комики 4k\Дмитрий Дедков - Одинёшенька ^(Стендап коцерт, 2022^).mkv^" ^"^)^"
    --title ^"Дмитрий Дедков 'Одинёшенька' ^| STAND UP КОНЦЕРТ^"
    --track-order 0:0,0:1
#>

<# Write-Host 'Parsing...' -ForegroundColor DarkMagenta
$prm = ('-hide_banner -loglevel error -select_streams v:0 -show_frames -print_format json -i "{0}" -o "{1}"' -f $fileIn, $fileFrames)
Start-Process -FilePath 'ffprobe.exe' -ArgumentList $prm -NoNewWindow -Wait
$frames = Get-Content -Path ([WildcardPattern]::Escape($fileFrames)) | ConvertFrom-Json
Write-Host ('frames count: {0}' -f $frames.frames.Count) -ForegroundColor DarkGreen


Write-Host 'Selecting keyframes...' -ForegroundColor DarkMagenta
$kf = $frames.frames
    | Where-Object { $_.pict_type -eq 'I' }
    | Select-Object *, @{Label = 'frame_number'; Expression = { [int]($_.pts * 25 / 1000) } } -First 2
Write-Host ('keyframe count: {0}' -f $kf.Count) -ForegroundColor DarkGreen
Write-Host 'Output...' -ForegroundColor DarkMagenta
$kf #>









$inFile = 'X:\temp\StaxRipTemp\The.Bear.s01e01. Система_temp\ID1 Russian [ru] {HDRezka Studio}.ac3'
$outOpusFile = 'X:\temp\StaxRipTemp\The.Bear.s01e01. Система_temp\out.opus'
$outAACFile = 'X:\temp\StaxRipTemp\The.Bear.s01e01. Система_temp\out.m4a'
# . ffmpeg -i "$inFile" -f flac - | opusenc --vbr --bitrate 350 - "$outOpusFile"
. ffmpeg -i "$inFile" -acodec pcm_s16le -f wav - | . 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe' --tvbr 91 -o "$outAACFile" -


$filterList = @(".flac")
Clear-Host
foreach ($f in (Get-ChildItem -Path 'y:\Video\Fargo_s03\audio_flac `[rus-NoAd`]\')) {
    if ($f.Extension -iin $filterList) {
        $outFile = [IO.Path]::ChangeExtension($f, 'aac')
        Write-Host $f -ForegroundColor Blue
        Write-Host $outFile -ForegroundColor DarkBlue
        # . 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe' --vbr --bitrate 384 "$f" "$outFile" --title "Original"
        . 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe' --tvbr 91 "$f" -o "$outFile"
        Write-Host ''
    }
}

<#
function Convert-ToOpus {
  [CmdletBinding()]
  param(
    [parameter(ValueFromPipeline)]$InputFileName
  )

  begin {
    [Collections.ArrayList]$inputObjects = @()
  }
  process {
    [void]$inputObjects.Add($InputFileName)
  }
  end {
    $inputObjects | Foreach ($f in $files) -Parallel {
        
    }
  }
}
#>



function Convert-ToOpus ([string]$inPath, [array]$filterList = @(".flac"), [string]$extraFilter, [string]$audioFormat) {
    # Clear-Host
    foreach ($f in (Get-ChildItem -Path $inPath)) {
        if ($f.Extension -iin $filterList) {
            $outFile = [IO.Path]::ChangeExtension($f, 'opus')
            Write-Host $f -ForegroundColor Blue
            Write-Host $outFile -ForegroundColor DarkBlue
            . 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\opus\opusenc.exe' --vbr --bitrate 384 "$f" "$outFile" --title "Original"
            # . 'X:\Apps\_VideoEncoding\StaxRip\Apps\Audio\qaac\qaac64.exe' --tvbr 91 "$f" -o "$outFile"
            Write-Host ''
        }
    }
}

Convert-ToOpus -inPath 'k:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\season 01\out_[SvtAv1EncApp]\' -filterList




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



<# 
# Remux mp4 to mkv with ffmpeg
# $ffmpeg\ffmpeg.exe -y -i file:$($file.FullName) -map 0 -c copy -c:s srt -vtag hevc "$($targetFull)\$($addon)"
# https://github.com/PmNz8/FFMPEG-dovi-mp4-to-mkv

$inFile = 'y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8.mp4'
$outFile = 'y:\Видео\Сериалы\Зарубежные\Пацаны (The Boys)\The.Boys.2019.S01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8\The.Boys.2019.S01E01.2160p.AMZN.WEB-DL.DDP.5.1.HDR.10.Plus.DoVi.P8.mkv'
. ffmpeg.exe -y -i "$inFile" -map 0 -c copy -c:s srt "$outFile"
#>












$s = 'crf 23 preset slow tune grain output-depth 10 amp subme 5 max-merge 5 rc-lookahead 40'
$s = 'x265 | x265_crf23_intra+'
#$s.Split(' ')
$s.Split('|')[1].Trim()









Add-Type -AssemblyName "X:\Apps\_VideoEncoding\StaxRip\StaxRip.exe" # -PassThru
$p = [StaxRip.ShortcutModule]::p
$g = [StaxRip.ShortcutModule]::g

$

$mis = [StaxRip.MediaInfoSharp]












<#
. "X:\Apps\_VideoEncoding\ffmpeg\yt-dlp.exe"
    --no-warnings
    --compat-options manifest-filesize-approx
    -j
    -o "%(title)s.%(ext)s"
    -S "vext:mkv,aext:m4a,vcodec:h265"
    -- "http://vk.com/video-218471730_456239612"
    > slovo.json
#>


. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'
Clear-Host
$InputFileList = Get-ChildItem -LiteralPath $Path -File:$true | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -like $extraFilter)) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue
# $fileListInfo = @(@())
$retVal = @()
foreach ($fileIn in $InputFileList) {
    Invoke-Process -commandPath 'X:\Apps\_VideoEncoding\ffmpeg\yt-dlp.exe' -commandArguments ''



    $j = Get-Content -Path 'y:\.temp\YT_y\list.txt' | ConvertFrom-Json
    foreach ($e in $j.entries) {
        $fv = $e.formats |
        Where-Object { (($_.width -eq '1920') -and ($_.protocol -like 'm3u8*')) } |
        Select-Object format_id, ext, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container |
        Sort-Object ext, resolution, abr
        $fa = $e.formats |
        Where-Object { ($_.ext -eq 'm4a') } |
        Sort-Object ext, resolution, abr |
        Select-Object format_id, ext, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container -Last 1

        # Write-Host $e.filename -ForegroundColor DarkBlue
        # Write-Host $e.webpage_url -ForegroundColor Blue
        # $fv | Format-Table -AutoSize
        # $fa | Format-Table -AutoSize

        # $str = ('. yt-dlp.exe --config-locations "X:\Apps\_VideoEncoding\ffmpeg\" --format {0}+{1} -o "[%(upload_date)s] %(title)s.%(ext)s" -- "{2}"' -f  $fv.format_id, $fa.format_id, $e.webpage_url)
        # $str
    }


}





. 'C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Function_Invoke-Process.ps1'
$playlistURL = 'https://vk.com/video/playlist/-220754053_27'
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
$strCommands = @(); $str=''
foreach ($e in $j.entries) {
    if ($e.requested_downloads.Count -ge 1) {
        $fv = $e.formats |
        Where-Object { (($_.width -ge '1920') -and ($_.protocol -like 'm3u8*')) } |
        Select-Object format_id, ext, width, height, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container -Last 1 |
        Sort-Object ext, resolution, abr
        $fa = $e.formats |
        Where-Object { ($_.ext -eq 'm4a') } |
        Sort-Object ext, resolution, abr |
        Select-Object format_id, ext, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container -Last 1

        Write-Host '*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*-*' -ForegroundColor Magenta
        Write-Host 'title   :', $e.title -ForegroundColor DarkBlue
        Write-Host 'filename:', $e.requested_downloads[0].filename -ForegroundColor Blue
        Write-Host 'webpgurl:', $e.webpage_url -ForegroundColor DarkCyan
        $fv | Format-Table -AutoSize
        $fa | Format-Table -AutoSize
        if (($fv.Count -gt 0) -and ($fa.Count -gt 0)) {
            if (($fv.Count -gt 1)) {
                Write-Host '>1 formats' -ForegroundColor DarkRed
            }
            $str = @(
                ("# {0}" -f $e.title)
                ('. yt-dlp.exe --config-locations "X:\Apps\_VideoEncoding\ffmpeg\" --format {0}+{1} --proxy "" --paths "temp:R:\\" --paths "y:\.temp\YT_y\Roast Battle+\" -- "{2}"' -f $fv.format_id, $fa.format_id, $e.webpage_url)
                )
            #$strCommands += @('# ', $e.title, $str)
            $strCommands += $str
            Write-Host $str -ForegroundColor DarkYellow
        }
        else {Write-Host 'NO suitable formats' -ForegroundColor Red }
    }
}
# Write-Host $strCommands -ForegroundColor DarkCyan
$strCommands

















$j = Get-Content -Path 'y:\.temp\YT_y\list.txt' | ConvertFrom-Json
$fv = @()
foreach ($e in $j.entries) {
    $r = $e.requested_formats.url[0] -match '^https:\/\/(?<uri>.*)\/video.*'
    $fv += $Matches.uri
    # Where-Object { (($_.width -eq '1920') -and ($_.protocol -like 'm3u8*')) } |
    #Select-Object format_id, ext, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container |
    #Sort-Object ext, resolution, abr
}
$fv | Select-Object -Unique |  Sort-Object

# $fa = $e.formats |
# Where-Object { ($_.ext -eq 'm4a') } |
# Sort-Object ext, resolution, abr |
# Select-Object format_id, ext, resolution, fps, filesize, tbr, protocol, vcodec, vbr, acodec, abr, asr, format_note, container -Last 1

# Write-Host $e.filename -ForegroundColor DarkBlue
# Write-Host $e.webpage_url -ForegroundColor Blue
# $fv | Format-Table -AutoSize
# $fa | Format-Table -AutoSize

# $str = ('. yt-dlp.exe --config-locations "X:\Apps\_VideoEncoding\ffmpeg\" --format {0}+{1} -o "[%(upload_date)s] %(title)s.%(ext)s" -- "{2}"' -f  $fv.format_id, $fa.format_id, $e.webpage_url)
# $str
}






$l = @(
    '[20230123] Roast Battle - Паша Техник x Алексей Щербаков ｜ Roast Battle LC #4.mkv',
    '[20230123] Roast Battle - Тимур Батрутдинов x Алексей Щербаков ｜ Roast Battle LC #10.mkv',
    '[20230123] Roast Battle - Щербаков х Бебуришвили х Яровицына. Roast Battle Frendlyfire. Специальный выпуск..mkv',
    '[20230123] Roast Battle - Щербаков х Макаров x Дедищев. Roast Battle Friendlyfire. Специальный выпуск.mkv',
    '[20230123] Roast Battle - Эльдар Джарахов x Алексей Щербаков ｜ Roast Battle LC #6.mkv',
    '[20230621] Roast Battle – Игорь Джабраилов х Сергей Орлов ｜ Roast Battle Labelcom #28.mkv',
    '[20230705] Roast Battle – Виктория Складчикова х Сергей Орлов ｜ Roast Battle Labelcom #29.mkv',
    '[20230719] Roast Battle – Леонид Слуцкий х Сергей Орлов ｜ Roast Battle Labelcom #30.mkv'
)

function Rename-RoasBattle {
    # $strRegexp = '^.*Roast Battle . (?<rbname>.*) . .* #(?<rbnum>\d+).*$'
    $strRegexp = '^.*\] (?<rbname>.*) . .* #(?<rbnum>\d+).*$'
    $l = Get-ChildItem 'y:\.temp\YT_y\Roast Battle+\audio_opus\' -File:$true -Recurse:$false
    $n = 0
    foreach ($f in $l) {
        #    $f
        if ($f -match $strRegexp) {
            $n++
            $rbName = $Matches.rbname
            $rbNum = [Int16]$Matches.rbnum
            $newFileName = ("{0}\Roast Battle Labelcom #{1:00} - {2}{3}" -f $f.Directory, $rbNum, $rbName, $f.Extension)
            Write-Host $n -ForegroundColor Magenta
            Write-Host $f -ForegroundColor Green
            Write-Host $newFileName -ForegroundColor Blue
            Rename-Item -LiteralPath $f -NewName $newFileName
        }
    }
}