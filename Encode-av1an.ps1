Param (
    [String]$InputFileDirName = ('
    X:\temp\InspectorGavrilov\vpy\
    ').Trim(), 
    [String]$encoder = 'rav1e', 
    [String]$targetQuality = '93', 
    [Int32]$prmAudioChannels = 0, 
    [Switch]$bRecurse = $false, 
    [Switch]$CommandLineGenerateOnly = $false
)

. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Get-ColorSpaceFromVideoFile.ps1
. C:\Users\pauln\OneDrive\Sources\Repos\PSScripts\Get-MediaInfoFromFiles.ps1


Clear-Host

<#
    ########################
    Override variable values
    ########################
#>

[string]$cqLevel = '30'
[bool]$bAddNoise = $false
[bool]$bWriteScript = $true

# x265
# $CommandLineGenerateOnly = $true
# [String]$encoder         = 'x265'
# [String]$targetQuality   = '92'
# [Int32]$prmAudioChannels = 0

# rav1e
# $CommandLineGenerateOnly = $true
# [String]$encoder = 'rav1e'
# [String]$targetQuality = '94'
# [Int32]$prmAudioChannels = 2

# aom
$CommandLineGenerateOnly = $true
[String]$encoder         = 'aom'
[String]$targetQuality   = '94'
[Int32]$prmAudioChannels = 2


<#  
    ########################
    Definitions
    ########################
#>

enum eEncoder {
    x265
    rav1e
    aom
    svt
}

$filterList = @(
    ".m2ts"
    ".mkv"
    ".mp4"
    ".vpy"
)

enum av1anChunkMethod {
    lsmash
    ffms2
    dgdecnv
    bestsource
    hybrid
}


switch ($prmAudioChannels) {
    0 {
        $prmLibOpus = ''
        $prmAAC = ''
    }
    2 {
        $prmLibOpus = "-c:a:0 libopus -b:a:0 160k -ac 2"
        $prmAAC = "-c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
    }
    6 {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC = "-c:a aac -q:a 3" # 5.1 ~516kbps
    }
    Default {
        $prmLibOpus = "-c:a libopus -b:a 320k -ac 6"
        $prmAAC = "-c:a aac -q:a 4 -ac 6" # 5.1 ~516kbps
    }
}

# $prmLibOpus = (@(
#     "-c:a:0 libopus -af:0 aformat=channel_layouts='7.1|5.1|stereo' -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=ru -metadata:s:a:0 title='[Невафильм DUB | Opus 5.1 Audio]'", 
#     "-c:a:1 libopus -b:a:1 160k -ac:1 2 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title='[LostFilm MVO | Opus 2.0 Audio]'", 
#     "-c:a:2 libopus -af:2 aformat=channel_layouts='7.1|5.1|stereo' -b:a:2 320k -ac:2 6 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title='[HDRezka MVO | Opus 5.1 Audio]'", 
#     "-c:a:3 libopus -b:a:3 160k -ac:3 2 -disposition:3 0 -metadata:s:a:3 language=ru -metadata:s:a:3 title='[TVShows MVO | Opus 2.0 Audio]'", 
#     "-c:a:4 libopus -af:4 aformat=channel_layouts='7.1|5.1|stereo' -b:a:4 320k -ac:4 6 -disposition:4 0 -metadata:s:a:4 language=en -metadata:s:a:4 title='[Original | Opus 5.1 Audio]'"
#     ) -join ' ')

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
    '-- preset 4'
    '-- lp 4'
)

$execAv1an = "X:\Apps\_VideoEncoding\av1an\av1an++.exe"
if (!(Test-Path -Path $execAv1an)) {
    Write-Host ("{0} не найден. Проверьте настройки." -f $execAv1an) -ForegroundColor Red
    Exit
}
else {
    Write-Host ("Используется {0}." -f $execAv1an) -ForegroundColor Green
}
Set-Location (Get-Item -Path $execAv1an).DirectoryName




<#  
    ########################
    Functions
    ########################
#>

function Convert-VideoFile {
    param (
        $InputFileName, 
        $OutputFileDirName = $InputFile.DirectoryName, 
        $encoder = [eEncoder]::rav1e, 
        $targetQuality = '92', 
        $cqLevel = $(switch ($encoder) {
                rav1e { '100' }
                aom { '22' }
                x265 { '23' }
                svt { '34' }
                Default { '' }
            })
        # $prmVideo='', $prmAudio=''
    )
    [System.Array]$strScript = @()
    [System.Array]$prmColors = @()
    $mInfo = Get-MI -file $InputFileName
    Clear-Variable "color_*"
    $color_params = Get-ColorSpaceFromVideoFile -inFileName $InputFileName
    $color_range = $color_params.color_range; 
    $color_space = $color_params.color_space; 
    $color_transfer = $color_params.color_transfer; 
    $color_primaries = $color_params.color_primaries; 
    $color_matrix = $(switch ($color_space) {
            'bt2020nc' { 'BT2020NCL' }
            Default { $color_space }
        })

    if (-not (Test-Path -LiteralPath $OutputFileDirName)) { New-Item -Path $OutputFileDirName -ItemType Directory | Out-Null }
    $InputFile = (Get-Item -LiteralPath $InputFileName)
    $OutputFileNameSuffix = ("[av1an][{0}_vmaf-Q{1}]" -f $encoder, $targetQuality)
    $OutputFileName = (Join-Path -Path $OutputFileDirName -ChildPath ("{0}{1}.mkv" -f $InputFile.BaseName, $OutputFileNameSuffix))

    $prmCommon = @(
        ("--target-quality {0}" -f $targetQuality)
        '--concat mkvmerge'
        '--probes 3'

        # Добавление шума
        if ($bAddNoise) {
            '--photon-noise 2', '--chroma-noise'
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
        # '--ffmpeg crop=3840:1608'
        # '--vmaf-filter crop=3840:1608'


        # Параметры av1an, зависящие от кодека видео
        if ($encoder -eq $([eEncoder]::x265)) {
            '--workers 3'
        }
        else {
            '--workers 8'
        }

        # Общие параметры av1an
        '--resume'
        '--verbose'
        '--log-level debug'
    )

    switch ($encoder) {
        svt {
            # SVT-AV1
            $prmAv1an = $prmCommon + @(
                '--encoder svt-av1', 
                ('--video-params ""{0}""' -f ($prmSVT -join " ")), 
                ('--audio-params ""{0}""' -f $prmLibOpus)
            )
        }
        aom {
            # AOMEnc
            $prmAv1an = $prmCommon + @(
                '--encoder aom', 
                ('--video-params ""{0}""' -f ($prmAOM -join " ")), 
                ('--audio-params ""{0}""' -f $prmLibOpus)
            )
        }
        x265 {
            # x265 color parameters
            [System.Array]$prmColors = @(
                if ($color_range -eq 'tv') { '--range limited' } else { '--range limited' }
                if ($color_primaries -inotin @('', $null, 'Unknown')) { ('--colorprim {0}' -f $color_primaries) } else { ('--colorprim bt709') }
                if ($color_matrix -inotin @('', $null, 'Unknown')) { ('--colormatrix {0}' -f $color_matrix) } else { ('--colormatrix bt709') }
                if (('--range limited' -in $prmColors) -and
                    ('--colorprim bt709' -in $prmColors) -and
                    ('--transfer bt709' -in $prmColors) -and
                    ('--colormatrix bt709' -in $prmColors)
                ) {
                    $prmColors = '--video-signal-type-preset BT709_YCC'
                }
            )
            <#
            if ($color_range -eq 'tv') { $prmColors += '--range limited' } else { $prmColors += ('--range limited') }
            if ($color_primaries -inotin @('', $null, 'Unknown')) { $prmColors += ('--colorprim {0}' -f $color_primaries) } else { $prmColors += ('--colorprim bt709') }
            if ($color_transfer -inotin @('', $null, 'Unknown')) { $prmColors += ('--transfer {0}' -f $color_transfer) } else { $prmColors += ('--transfer bt709') }
            if ($color_matrix -inotin @('', $null, 'Unknown')) { $prmColors += ('--colormatrix {0}' -f $color_matrix) } else { $prmColors += ('--colormatrix bt709') }
            if (
                ('--range limited' -in $prmColors) -and
                ('--colorprim bt709' -in $prmColors) -and
                ('--transfer bt709' -in $prmColors) -and
                ('--colormatrix bt709' -in $prmColors)
            ) {
                # BT709_YCC:       --colorprim bt709 --transfer bt709 --colormatrix bt709 --range limited --chromaloc 0
                $prmColors = '--video-signal-type-preset BT709_YCC'
            }
            #>

            $prmAv1an = $prmCommon + @(
                '--encoder x265'
                '--min-q=15 --max-q=35'
                ('--video-params ""{0}""' -f (($prmX265.Trim() + $prmColors.Trim()) -join " "))
                ('--audio-params ""{0}""' -f $prmAAC)
            )
        }
        Default {         
            # rav1e color parameters
            [System.Array]$prmColors = @(
                if ($color_range -eq 'tv') { '--range limited' } else { '--range limited' }
                if ($color_primaries -inotin @('', $null, 'Unknown')) { ('--primaries {0}' -f $color_primaries) } else { '--primaries BT709' }
                if ($color_transfer -inotin @('', $null, 'Unknown')) { ('--transfer {0}' -f $color_transfer) } else { '--transfer BT709' }
                if ($color_matrix -inotin @('', $null, 'Unknown')) { ('--matrix {0}' -f $color_matrix) } else { '--matrix BT709' }
            )
            # Video parameters
            $prmAv1an = $prmCommon + @(
                '--encoder rav1e'
                '--min-q=60 --max-q=150'
                ('--video-params ""{0}""' -f (($prmRav1e.Trim() + $prmColors.Trim()) -join " "))
                ('--audio-params ""{0}""' -f $prmLibOpus)
            )
        }
    }

    # Write-Host ("@echo {0}" -f $OutputFileName) -ForegroundColor DarkYellow

    if ((Test-Path -LiteralPath $OutputFileName -PathType Leaf) -eq $true) {
        Write-Host "# File exists, skipping..." -ForegroundColor Magenta
        Return
    }
    else {
        # Write-Host 'Write-Host "Waiting 60 seconds..." -Foregroundcolor DarkYellow; Start-Sleep -Seconds 60'
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
            Start-Process -FilePath $execAv1an -ArgumentList ($prmAv1an -join ' ') -Wait -NoNewWindow
        }
    }
    Return $strScript
} # End Function






$OutputDirName = Join-Path -Path $InputFileDirName -ChildPath 'out_[av1an]'
if (-not (Test-Path -LiteralPath $OutputDirName)) { New-Item -Path $OutputDirName -ItemType Directory | Out-Null }
$InputFileList = Get-ChildItem -LiteralPath $InputFileDirName -File -Recurse:$bRecurse | Where-Object { (($_.Extension -iin $filterList) -and ($_.BaseName -inotlike '*`[av1an`]*')) }
Write-Host ("Найдено файлов: {0}" -f $InputFileList.Count) -ForegroundColor Blue


Write-Host ("Generating ps1 script...") -ForegroundColor DarkGreen
$strScript1 = @()
foreach ($InputFileName in $InputFileList) {
    <#
    $s = @(
        ("`r`n`$fn = '{0}'" -f $InputFileName),
        'Write-Host ("`r`n[{0}] {1}" -f (Get-Date), $fn) -ForegroundColor DarkMagenta'
    )
    Write-Host ($s -join "`r`n")
    #>

    $strScript1 += Convert-VideoFile -InputFileName $InputFileName -OutputFileDirName $OutputDirName -encoder $encoder -targetQuality $targetQuality # -prmVideo $prmX265 -prmAudio $prmAAC

}

if ($bWriteScript) {
    # Write-Host ($strScript1 -join "`r`n") -ForegroundColor Green
    $striptFileName = (Join-Path -Path $InputFileDirName -ChildPath ('encode_[{0}].ps1' -f $encoder))
    Write-Host ("Writing ps1 script: {0} ... " -f $striptFileName) -ForegroundColor DarkGreen -NoNewline
    $strScript1 | Out-File -LiteralPath $striptFileName -Encoding utf8 -Force
    Write-Host ("OK") -ForegroundColor Green
}
else {
    Write-Host ("Skip writing ps1 file" -f $striptFileName) -ForegroundColor DarkGreen -NoNewline
    Write-Host ($strScript1) -ForegroundColor Gray
}


































<# Обрезка ffmpeg

        # '-i ""$ifn""', 
        # '-o ""$ofn""', 
        # '-l ""$lfn""', 
        
        #("-i ""{0}""" -f $InputFileName), 
        #("-o ""{0}""" -f $OutputFileName), 
        # '--ffmpeg "-vf crop=3840:1608:0:276"', 
        # '--ffmpeg "-vf crop=3840:1600:0:280"', '--vmaf-filter "crop=3840:1600:0:280"', '--vmaf-res "3840x1600"'
        # ('--log-file ".\logs\[{0:yyyyMMdd_HHmmss}]_{1}"' -f (Get-Date), $logFileName), "--log-level DEBUG",
#>




<# Различные параметры кодирования звука

# rav1e
# $prmLibOpus = '-c:a:0 libopus -b:a:0 280k -c:a:1 libopus -b:a:1 280k -c:a:2 libopus -b:a:2 144k -c:a:3 libopus -b:a:3 144k'
# $prmLibOpus = '-c:a:0 libopus -b:a:0 320k -ac:0 6 -filter:0 aformat=channel_layouts=5.1 -c:a:1 libopus -b:a:1 320k -ac:1 6 -filter:1 aformat=channel_layouts=5.1 -c:a:2 libopus -b:a:2 160k -c:a:3 libopus -b:a:3 160k'
# $prmLibOpus = '-c:a:0 copy -c:a:1 libopus -b:a:1 160k'




# $prmLibOpus = '-c:a:1 libopus -b:a:1 320k -ac 6 -c:a:2 libopus -b:a:2 160k -ac 2'
# # $prmLibOpus = "-c:a:0 libopus -b:a:0 136k -ac 2  -c:a:1 libopus -b:a:1 320k -ac 6  -c:a:2 libopus -b:a:2 320k -ac 6"

# $prmLibOpus = '-c:a:0 copy -c:a:1 libopus -b:a:1 160k'

<# Black List
$prmLibOpus = (@(
    "-c:a:0 libopus -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=en -metadata:s:a:0 title='[Original | Opus 5.1 Audio]'", 
    "-c:a:1 libopus -b:a:1 320k -ac:1 6 -filter:1 aformat=channel_layouts=5.1 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title='[Lostfilm | Opus 5.1 Audio]'", 
    "-c:a:2 libopus -b:a:2 160k -ac:2 2 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title='[SET | Opus 2.0 Audio]'"
) -join ' ')
#>

<#
# Fargo
$prmLibOpus = (@(
    "-c:a:0 libopus -af:0 aformat=channel_layouts='7.1|5.1|stereo' -b:a:0 320k -ac:0 6 -disposition:0 0 -metadata:s:a:0 language=ru -metadata:s:a:0 title='[LostFilm | Opus 5.1 Audio]'", 
    "-c:a:1 libopus -af:1 aformat=channel_layouts='7.1|5.1|stereo' -b:a:1 320k -ac:1 6 -disposition:1 default -metadata:s:a:1 language=ru -metadata:s:a:1 title='[Кубик в Кубе | Opus 5.1 Audio]'", 
    "-c:a:2 libopus -af:2 aformat=channel_layouts='7.1|5.1|stereo' -b:a:2 320k -ac:2 6 -disposition:2 0 -metadata:s:a:2 language=ru -metadata:s:a:2 title='[NewStudio | Opus 5.1 Audio]'", 
    "-c:a:3 libopus -af:3 aformat=channel_layouts='7.1|5.1|stereo' -b:a:3 320k -ac:3 6 -disposition:3 0 -metadata:s:a:3 language=ru -metadata:s:a:3 title='[Ideafilm | Opus 5.1 Audio]'", 
    "-c:a:4 libopus -b:a:4 160k -ac:4 2 -disposition:4 0 -metadata:s:a:4 language=ru -metadata:s:a:4 title='[Первый канал | Opus 2.0 Audio]'",
    "-c:a:5 libopus -af:5 aformat=channel_layouts='7.1|5.1|stereo' -b:a:5 320k -ac:5 6 -disposition:5 0 -metadata:s:a:5 language=en -metadata:s:a:5 title='[Original | Opus 5.1 Audio]'", 
    "-c:a:6 libopus -b:a:6 160k -ac:6 2 -disposition:6 0 -metadata:s:a:6 language=en -metadata:s:a:6 title='[Commentary | Opus 2.0 Audio]'"
) -join ' ')
#>


<# $prmLibOpus = "-c:a libopus -b:a 136k -ac 2"
#$prmLibOpus = "-c:a libopus -b:a 280k -ac 6"
$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 2" # Stereo ~172kbps
#$prmAAC = "ffmpeg -c:a aac -q:a 4 -ac 6" # Stereo ~516kbps #>


#>