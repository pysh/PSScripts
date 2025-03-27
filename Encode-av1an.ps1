Param (
    [String]$InputFileDirName = ('
    y:\.temp\Сериалы\Зарубежные\Ходячие мертвецы\season 02\test\
    ').Trim(), 
    [Switch]$bRecurse = $false, 
    [String]$encoder = 'rav1e', 
    [String]$targetQuality = '93', 
    [Int32]$prmAudioChannels = 0, 
    [Switch]$CommandLineGenerateOnly = $true
)

Clear-Host

# Load external functions
. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\tools.ps1

#Filter settings
$filterList = @(
    ".m2ts", ".mkv", ".mp4", ".vpy"
)
$extraFilter = "*"

# Crop parameters
$crop = @([PSCustomObject]@{
        crop_left   = 0;
        crop_right  = 0;
        crop_top    = 0;
        crop_bottom = 0;
        cropping    = $false;
    }
)
[string]$cropPrms = ("crop=in_w-{0}-{1}:in_h-{2}-{3}:{0}:{2}" -f $crop.crop_left, $crop.crop_right, $crop.crop_top, $crop.crop_bottom)

# Audio encoder parameters
switch ($prmAudioChannels) {
    -1 {
        $prmLibOpus = '-an'
        $prmAAC = '-an'
    }
    0 {
        $prmLibOpus = ''
        $prmAAC = ''
    }
    2 {
        $prmLibOpus = "-c:a:0 libopus -b:a:0 160k -ac 2"
        $prmAAC = "-c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
    }
    6 {
        $prmLibOpus = "-c:a libopus -b:a 350k -ac 6"
        $prmAAC = "-c:a aac -q:a 3" # 5.1 ~516kbps
    }
    Default {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC = "-c:a aac -q:a 4 -ac 6" # 5.1 ~516kbps
    }
}

# av1an executable path
$execAv1an = Get-Command av1an.exe -ErrorAction SilentlyContinue
if (-not $execAv1an) {
    Write-Host "av1an.exe не найден. Проверьте настройки." -ForegroundColor Red
    Exit
}
Set-Location (Get-Item -Path $execAv1an.Source).DirectoryName
Write-Host ("Используется {0}." -f $execAv1an.Source) -ForegroundColor Green



# Video encoder parameters
enum eEncoder {
    x265
    rav1e
    aom
    svt
}
Enum av1anChunkMethod {
    lsmash
    ffms2
    dgdecnv
    bestsource
    hybrid
}
[bool]$CommandLineGenerateOnly = $true
[eEncoder]$encoder = 'rav1e'
[String]$targetQuality = '91'
[Int32]$prmAudioChannels = 0
[string]$cqLevel = '30'
[bool]$bAddNoise = $true
[bool]$bWriteScript = $true

# Encoder specific parameters
$prmRav1e = @(
    '--speed 6', 
    '--quantizer 93', 
    # '--threads 8', 
    # '--tiles 4', 
    # '--level 5.0',
    '--no-scene-detection'
)

$prmX265 = @(
    "--crf 23 --preset slow --output-depth 10", 
    "--amp --subme 5 --max-merge 5 --rc-lookahead 40 --gop-lookahead 34 --ref 5", 
    "--no-strong-intra-smoothing --constrained-intra"
)

$prmAOM = @(
    # aomenc-av1 with grain synth and higher efficiency (no anime)
    # https://www.reddit.com/r/AV1/comments/n4si96/encoder_tuning_part_3_av1_grain_synthesis_how_it/
    '--bit-depth=10 --end-usage=q --cq-level=21 --cpu-used=4 --arnr-strength=4',
    '--tile-columns=1 --tile-rows=0 --lag-in-frames=35 --enable-fwd-kf=1 --kf-max-dist=240, --aq-mode=1', 
    '--max-partition-size=64 --enable-qm=1 --enable-chroma-deltaq=1 --quant-b-adapt=1 --enable-dnl-denoising=0 --denoise-noise-level=5'
)

$prmSVT = @(
    '--rc 0'
    '--preset 4'
    '--sharpness 1'
    '--frame-luma-bias 10'
)

function Get-AudioTrackParameters {
    param (
        [Parameter(Mandatory = $true)]
        [string]$InputFileName
    )

    # Используем ffprobe для получения информации о аудиопотоках
    $audioTracks = ffprobe -v error -select_streams a -show_entries stream=index,codec_name,channels,channel_layout:stream_disposition:stream_tags=language,title -of json $InputFileName | ConvertFrom-Json

    $prmLibOpus = @()
    foreach ($track in $audioTracks.streams) {
        $index = $track.index - 1
        $language = if ($track.tags.language) { $track.tags.language } else { "und" }
        $title = if ($track.tags.title) { $track.tags.title } else { "" }
        $channels = $track.channels
        $channelsLayout = $track.channel_layout
        $bitrate = if ($channels -eq 2) { "160k" } else { "320k" }
        $defaultTrack = if ($track.disposition.default -eq 1) { "default" } else { "0" }
        [bool]$originalTrack = ($track.disposition.original -eq 1)

        $channelString = @(
            "-map 0:a:$index"
            "-c:a:$index libopus"
            if ($channels -gt 2 -and $channelsLayout -like "*(side)*") { "-af:a:$index aformat=channel_layouts='7.1|5.1|stereo'" }
            "-b:a:$index $bitrate"
            "-ac:a:$index $channels"
            "-disposition:a:$index $defaultTrack"
            "-metadata:s:a:$index language=$language"
            "-metadata:s:a:$index title='$title'"
            if ($title -ne "") {
                "-metadata:s:a:$index title='$title'"
            }
            elseif ($originalTrack) {
                "-metadata:s:a:$index title='Original Audio'"
            }
        ) -join " "
        $prmLibOpus += $channelString
        #         $prmLibOpus = (@(
        #             ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} default -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[HDRezka Studio | Opus 5.1 Audio]"' -f '1')
        #             ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 160k -ac:{0} 2 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[LostFilm | Opus 2.0 Audio]"' -f '2')
        #             ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=ru -metadata:s:a:{0} title="[TVShows | Opus 5.1 Audio]"' -f '0')
        #             ('-map 0:a:{0} -c:a:{0} libopus -b:a:{0} 320k -ac:{0} 6 -disposition:{0} 0 -metadata:s:a:{0} language=en -metadata:s:a:{0} title="[Original | Opus 5.1 Audio]"' -f '3')
        # )
    }

    return $prmLibOpus
}

function Convert-VideoFile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputFileName, # Source video file
        
        [Parameter(Mandatory = $false)]
        [string]$OutputFileDirName, # Output directory (defaults to input directory)
        
        [Parameter(Mandatory = $false)]
        [eEncoder]$encoder = [eEncoder]::rav1e, # Encoder type
        
        [Parameter(Mandatory = $false)]
        [string]$targetQuality = '92', # Target VMAF quality
        
        [Parameter(Mandatory = $false)]
        [string]$cqLevel = $(switch ($encoder) {
                # Constant quality level per encoder
                rav1e { '100' }
                aom { '22' }
                x265 { '23' }
                svt { '32' }
                Default { '' }
            })
    )

    begin {
        [System.Array]$strScript = @()
        $ColorParameters = Get-VideoColorMappings -VideoPath $InputFileName
        
        # Validate input file exists
        if (-not (Test-Path -LiteralPath $InputFileName)) {
            throw "Input file not found: $InputFileName"
        }

        # Set output directory if not specified
        if (-not $OutputFileDirName) {
            $OutputFileDirName = Split-Path -Path $InputFileName -Parent
        }
    }

    process {
        # Create output directory if needed
        if (-not (Test-Path -LiteralPath $OutputFileDirName)) { 
            New-Item -Path $OutputFileDirName -ItemType Directory | Out-Null 
        }

        $InputFile = (Get-Item -LiteralPath $InputFileName)
        $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
        $OutputFileName = (Join-Path -Path $OutputFileDirName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))

        # Skip if output exists
        if (Test-Path -LiteralPath $OutputFileName -PathType Leaf) {
            Write-Host "# File exists, skipping..." -ForegroundColor Magenta
            return
        }

        $prmCommon = @(
            ("--target-quality {0}" -f $targetQuality)
            '--concat mkvmerge'
            '--probes 3'
            ('--temp ""R:\temp\{0}\{1:yyyyMMdd_HHmmss.fff}""' -f $InputFile.BaseName, $(Get-Date))

            # Добавление шума
            if ($bAddNoise) {
                '--photon-noise 4', '--chroma-noise'
            }

            # Декодер
            if ($mInfo.Format -in @('HEVC_', 'AVC_')) {
                '--chunk-method dgdecnv'
            }
            else {
                '--chunk-method lsmash'
            }

            # Параметры av1an, зависящие от разрешения видео
            if ($mInfo.Height -gt 1080) {
                # '--vmaf-path ""vmaf_4k_v0.6.1.json""'
                '--vmaf-res iw:ih'
                '--vmaf-version ""vmaf_4k_v0.6.1""'
            }
            # Обрезка кадра
            # if ($cropPrms) {
            #     ('--ffmpeg ""-vf {0}""' -f $cropPrms)
            #     ('--vmaf-filter ""{0}""' -f $cropPrms)
            # }

            # Параметры av1an, зависящие от кодека видео
            if ($encoder -eq $([eEncoder]::x265)) {
                '--workers 3'
            }
            elseif ($encoder -eq $([eEncoder]::svt)) {
                '--workers 2'
            }
            else {
                '--workers 8'
            }

            # Общие параметры av1an
            '--resume'
            '--verbose'
            '--log-level debug'
        )

        # Build encoder-specific parameters
        switch ($encoder) {
            # SVT-AV1 specific parameters
            svt {
                # SVT-AV1 color space parameters
                $prmColors = @(
                    if ($ColorParameters.Range.svt.Count -gt 0) {
                        $ColorParameters.Range.svt.param
                        $ColorParameters.Range.svt.value
                    }
                )
                # Av1an parameters
                $prmAv1an = $prmCommon + @(
                    '--encoder svt-av1'
                    '--min-q=31 --max-q=50'
                    ('--video-params ""{0}""' -f ($prmSVT + $prmColors -join " "))
                    ('--audio-params ""{0}""' -f $prmLibOpus)
                )
            }
            # AOM-AV1 specific parameters
            aom {
                # aom color space parameters
                $prmColors = @(
                    if ($ColorParameters.Range.aomenc.Count -gt 0) {
                        $ColorParameters.Range.aomenc.param
                        $ColorParameters.Range.aomenc.value
                    }
                )
                # Av1an parameters
                $prmAv1an = $prmCommon + @(
                    '--encoder aom', 
                    ('--video-params ""{0}""' -f ($prmAOM + $prmColors -join " ")), 
                    ('--audio-params ""{0}""' -f $prmLibOpus)
                )
            }
            # x265 specific parameters
            x265 {
                # x265 color space parameters
                $prmColors = @(
                    if ($ColorParameters.Range.x265.Count -gt 0) {
                        $ColorParameters.Range.x265.param
                        $ColorParameters.Range.x265.value
                    }
                )

                # Av1an parameters
                $prmAv1an = $prmCommon + @(
                    '--encoder x265'
                    '--min-q=15 --max-q=35'
                    ('--video-params ""{0}""' -f (($prmX265.Trim() + $prmColors.Trim()) -join " "))
                    ('--audio-params ""{0}""' -f $prmAAC)
                )
            }
            # rav1e specific parameters
            Default {         
                # rav1e color space parameters
                $prmColors = @(
                    if ($ColorParameters.Range.rav1e.Count -gt 0) {
                        $ColorParameters.Range.rav1e.param
                        $ColorParameters.Range.rav1e.value
                    }
                )
                # Av1an parameters
                $prmAv1an = $prmCommon + @(
                    '--encoder rav1e'
                    '--min-q=60 --max-q=150'
                    ('--video-params ""{0}""' -f ($prmRav1e + $prmColors -join " "))
                    ('--audio-params ""{0}""' -f $prmLibOpus)
                )
            }
        }

        # Generate script content
        $curDate = (Get-Date)
        [string]$tmpPath = 'Y:\av1an_tmp'
        [string]$tmpFileName = Join-Path -Path $tmpPath -ChildPath ('{0:yyyyMMdd_HHmmss_fff}{1}' -f ($curDate), $InputFileName.Extension)
        [string]$tmpFileName2 = Join-Path -Path $tmpPath -ChildPath ('{0:yyyyMMdd_HHmmss_fff}_out{1}' -f ($curDate), $InputFileName.Extension)

        $info = ("[{0}] {1}x{2} @ {3} {4} ({5}, {6} frames)  =  {7:n2} Mb" -f 
            $mInfo.Format, $mInfo.Width, $mInfo.Height, $mInfo.FrameRate, $mInfo.FrameRateMode, $mInfo.Duration, $mInfo.FrameCount, ($InputFileName.Length / 1Mb))
        $strScript += @(
            '', 
            # Присваиваем переменные
            ('$ifn  = ''{0}'';' -f $InputFileName),
            ('$ofn  = ''{0}'';' -f $OutputFileName),
            ('$tfn  = ''{0}'';' -f $tmpFileName), 
            ('$tfn2 = ''{0}'';' -f $tmpFileName2),
            ('$tsvg = [System.IO.Path]::ChangeExtension($tfn2, "svg")'), 
            ('$tvmaf= [System.IO.Path]::ChangeExtension($tfn2, "json")'),
            ('$osvg = [System.IO.Path]::ChangeExtension($ofn, "svg")'),
            ('$ovmaf= [System.IO.Path]::ChangeExtension($ofn, "json")'),
            ('$lfn  = ''.\logs\[{0:yyyyMMdd_HHmmss}]_{1}'' -f (Get-Date), [System.IO.Path]::GetFileName($ofn)'), 
            ('$prm  = "-i ""$tfn"" -o ""$tfn2"" -l ""$lfn"" {0}"' -f ($prmAv1an -join ' ')), 
            'Write-Host ("`r`n`r`n")',
            'Write-Host ("[{0}] IN  {1}" -f (Get-Date), $ifn) -ForegroundColor Magenta',
            'Write-Host ("[{0}] TMP {1}" -f (Get-Date), $tfn) -ForegroundColor Magenta', 
            'if (Test-Path -LiteralPath $ofn) {',
            'Write-Host ("[{0}] OUT {1}" -f (Get-Date), $ofn) -ForegroundColor DarkMagenta',
            '    Write-Host "Skiping file" -ForegroundColor DarkYellow',
            '} else {', 

            # Создаем папки
            ('if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($ofn))) ) { New-Item -Path [System.IO.Path]::GetDirectoryName($ofn) -ItemType Directory | Out-Null }'), 
            ('if (-not (Test-Path -LiteralPath ([System.IO.Path]::GetDirectoryName($tfn))) ) { New-Item -Path [System.IO.Path]::GetDirectoryName($tfn) -ItemType Directory | Out-Null }'), 
            
            # Пишем информацию в консоль
            # 'Write-Host ("`r`n[{0}] IN  {1}" -f (Get-Date), $ifn) -ForegroundColor Magenta',
            'Write-Host ("[{0}] OUT {1}" -f (Get-Date), $ofn) -ForegroundColor DarkMagenta',
            "Write-Host ""$info"" -ForegroundColor DarkYellow",
            'Write-Host ("[{0}] LOG {1}" -f (Get-Date), $lfn) -ForegroundColor Gray',
            'Write-Host ($prm) -ForegroundColor DarkGray',
            
            # Копируем файл во временную директорию
            'Write-Host ("Копируем файл во временную директорию: {0}" -f $tfn) -ForegroundColor DarkMagenta',
            'Copy-Item -Path ([WildcardPattern]::Escape($ifn)) -Destination ([WildcardPattern]::Escape($tfn)) -Force',

            # Переходим в папку с авианом
            ('Set-Location -LiteralPath ''{0}\'';' -f (Get-Item $execAv1an).Directory),

            # Запускаем av1an с параметрами $prm
            ('Start-Process -FilePath ".\{0}" -ArgumentList ($prm) -Wait -NoNewWindow;' -f (Get-Item $execAv1an).Name), 
            
            # Считаем размеры
            '$s1=(Get-Item -Path $tfn).Length; $s2=(Get-Item -Path $tfn2).Length',
            '$prc=[Math]::Round($s2/$s1*100,2)',
            'Write-Host ("[{0}] INF {1:n2} Мб  ==>  {2:n2} Мб  =  {3}%" -f (Get-Date), ($s1 /1Mb), ($s2 /1Mb), $prc) -ForegroundColor DarkGreen',

            # Перемещаем кодированный файл
            'Write-Host ("[{0}] MOV {1} TO {2}" -f (Get-Date), $tfn2, $ofn) -ForegroundColor Gray',
            'Move-Item -Path ([WildcardPattern]::Escape($tfn2)) -Destination $ofn',

            'Write-Host ("[{0}] MOV {1} TO {2}" -f (Get-Date), $tsvg, $osvg) -ForegroundColor Gray',
            'Move-Item -Path ([WildcardPattern]::Escape($tsvg)) -Destination $osvg',

            'Write-Host ("[{0}] MOV {1} TO {2}" -f (Get-Date), $tvmaf, $ovmaf) -ForegroundColor Gray',
            'Move-Item -Path ([WildcardPattern]::Escape($tvmaf)) -Destination $ovmaf',

            # Удаляем временный файл
            'Write-Host ("[{0}] DEL {1}" -f (Get-Date), $tfn) -ForegroundColor Gray',
            'Remove-Item -Path ([WildcardPattern]::Escape($tfn))',
            '}'
        )
        # $strScript += ('Set-Location -LiteralPath "{0}\";' -f (Get-Item $execAv1an).Directory)
        # $strScript += ('. .\{0} {1}' -f (Get-Item $execAv1an).Name, ($prmAv1an -join ' '))
        # Write-Host $strScript -ForegroundColor DarkBlue
        # Write-Host ('Set-Location -LiteralPath "{0}\";' -f (Get-Item $execAv1an).Directory) -ForegroundColor Cyan -NoNewline
        # Write-Host (' . .\{0} {1}' -f (Get-Item $execAv1an).Name, ($prmAv1an -join ' ')) -ForegroundColor DarkBlue
        if (-not $CommandLineGenerateOnly) {
            # Actually runs the encoding process
            Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join ' ') -Wait -NoNewWindow
        }
    } end {
        return $strScript
    }
} # End Function



$OutputDirName = Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path -LiteralPath $OutputDirName)) { New-Item -Path $OutputDirName -ItemType Directory | Out-Null }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*') -and ($_.BaseName -like $extraFilter)) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue

Write-Host ("Generating ps1 script...") -ForegroundColor DarkGreen
$strScript1 = @()
foreach ($InputFileName in $InputFileList) {
    $prmLibOpus = (Get-AudioTrackParameters -InputFileName $InputFileName) -join ' '
    $strScript1 += Convert-VideoFile -InputFileName $InputFileName -OutputFileDirName $OutputDirName -encoder $encoder -targetQuality $targetQuality # -prmVideo $prmX265 -prmAudio $prmAAC
}

if ($bWriteScript) {
    # Write-Host ($strScript1 -join "`r`n") -ForegroundColor Green
    $striptFileName = (Join-Path -Path $InputFileDirName -ChildPath ('encode_[{0}].ps1' -f $encoder))
    Write-Host ("Writing ps1 script: {0} ... " -f $striptFileName) -ForegroundColor DarkGreen -NoNewline
    if ($CommandLineGenerateOnly) {
        $strScript1 | Out-File -LiteralPath $striptFileName -Encoding utf8 -Force
    }
    else {
        Write-Host $strScript1 -ForegroundColor DarkCyan
    }
    Write-Host ("OK") -ForegroundColor Green
}
else {
    Write-Host ("Skip writing ps1 file" -f $striptFileName) -ForegroundColor DarkGreen -NoNewline
    Write-Host ($strScript1) -ForegroundColor Gray
}
