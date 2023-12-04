
$mkvMergeApp = 'c:\Program Files\MKVToolNix\mkvmerge.exe'
$inFileName = 'W:\Видео\Сериалы\Зарубежные\Одни из нас (The Last Of Us)\season 01\The.Last.of.Us.S01E.2160p.HMAX.WEB-DL.x265.HDR.Master5\out_[av1an]\The.Last.of.Us.S01E03.2160p.HDR.Master5[av1an][rav1e_vmaf-Q95].mkv'
$outFileName = [System.IO.Path]::ChangeExtension($inFileName, '_HDR_[my].mkv')

<# 
$prmIngestHDR = @(
    $mkvMergeApp,
    ("-o {0}" -f $inFileName),
    '--colour-matrix 0:9',
    '--colour-range 0:1',
    '--colour-transfer-characteristics 0:16',
    '--colour-primaries 0:9',
    '--max-content-light 0:1000',
    '--max-frame-light 0:300',
    '--max-luminance 0:1000',
    '--min-luminance 0:0.01',
    '--chromaticity-coordinates 0:0.68,0.32,0.265,0.690,0.15,0.06',
    '--white-colour-coordinates 0:0.3127,0.3290',
    $outFileName
)
#>

$prmIngestHDR = @(
    ('-o "{0}"' -f $outFileName),
    '--color-matrix-coefficients 0:9 ', # 0: GBR, 1: BT709, 2: unspecified, 3: reserved, 4: FCC, 5: BT470BG, 6: SMPTE 170M, 7: SMPTE 240M, 8: YCOCG, 9: BT2020 non-constant luminance, 10: BT2020 constant luminance
    '--color-bits-per-channel 0:10 ', 
    # '--chroma-subsample 0:88 ', 
    '--color-range 0:1 ', #(0: unspecified, 1: broadcast range, 2: full range (no clipping), 3: defined by MatrixCoefficients/TransferCharacteristics)
    '--color-transfer-characteristics 0:16 ', # 0: reserved, 1: ITU-R BT.709, 2: unspecified, 3: reserved, 4: gamma 2.2 curve, 5: gamma 2.8 curve, 6: SMPTE 170M, 7: SMPTE 240M, 8: linear, 9: log, 10: log sqrt, 11: IEC 61966-2-4, 12: ITU-R BT.1361 extended color gamut, 13: IEC 61966-2-1, 14: ITU-R BT.2020 10 bit, 15: ITU-R BT.2020 12 bit, 16: SMPTE ST 2084, 17: SMPTE ST 428-1; 18: ARIB STD-B67 (HLG)
    '--color-primaries 0:9 ', # 0: reserved, 1: ITU-R BT.709, 2: unspecified, 3: reserved, 4: ITU-R BT.470M, 5: ITU-R BT.470BG, 6: SMPTE 170M, 7: SMPTE 240M, 8: FILM, 9: ITU-R BT.2020, 10: SMPTE ST 428-1, 22: JEDEC P22 phosphors
    <#
    # '--cb-subsample 0:77 ', 
    # '--chroma-siting 0:66 ', 
    '--chromaticity-coordinates 0:111 ', 
    '--white-color-coordinates 0:222 ', #>
    '--max-content-light 0:501 ', 
    '--max-frame-light 0:235 ', 
    '--max-luminance 0:1023 ', 
    '--min-luminance 0:0', 
    ('"{0}"' -f $inFileName)
)

Write-Host $prmIngestHDR -ForegroundColor DarkGreen

Start-Process -FilePath $mkvMergeApp -ArgumentList ($prmIngestHDR) -Wait -NoNewWindow