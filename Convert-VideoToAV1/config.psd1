@{
    # Пути к инструментам
    Tools      = @{
        FFmpeg         = "ffmpeg.exe"
        FFprobe        = "ffprobe.exe"
        MkvMerge       = "mkvmerge.exe"
        MkvExtract     = "mkvextract.exe"
        MkvPropedit    = "mkvpropedit.exe"
        VSPipe         = "C:\Program Files\VapourSynth\core\vspipe.exe"
        x265           = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\x265\x265.exe'
        SvtAv1Enc      = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
        SvtAv1EncESS   = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-Essential\SvtAv1EncApp.exe'
        SvtAv1EncHDR   = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-HDR\SvtAv1EncApp.exe'
        SvtAv1EncPSYEX = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-PSYEX\SvtAv1EncApp.exe'
        Rav1eEnc       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\rav1e\rav1e.exe'
        AomAv1Enc      = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\AOMEnc\aomenc.exe'
        OpusEnc        = 'd:\Sources\media-autobuild_suite\local64\bin-audio\opusenc.exe'
        AutoCrop       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe'
    }

    # Параметры обработки
    Processing = @{
        DefaultThreads     = 10
        keepTempAudioFiles = $false
        DeleteTempFiles    = $true
        AutoCropThreshold  = 1000
        TempDir            = "r:\Temp\"
        VSPipeMethod       = "vspipe"  # Возможные значения: "vspipe", "ffmpeg"
    }
    
    Encoding   = @{
        # Доступные энкодеры (основные исполняемые файлы)
        AvailableEncoders = @{
            x265           = 'Tools.x265'
            SvtAv1Enc      = 'Tools.SvtAv1Enc'
            SvtAv1EncESS   = 'Tools.SvtAv1EncESS'
            SvtAv1EncHDR   = 'Tools.SvtAv1EncHDR'
            SvtAv1EncPSYEX = 'Tools.SvtAv1EncPSYEX'
            Rav1eEnc       = 'Tools.Rav1eEnc'
            AomAv1Enc      = 'Tools.AomAv1Enc'
        }
        
        # Энкодер по умолчанию
        DefaultEncoder    = 'SvtAv1EncESS'
        
        # Управление копированием (можно переопределить параметрами скрипта)
        Audio             = @{
            CopyAudio = $false  # true = копировать без перекодировки
            Bitrates  = @{
                Stereo   = "192k"
                Surround = "384k"
                Multi    = "480k"
            }
        }
        
        Video             = @{
            CopyVideo     = $false
            CropRound     = 2
            XtraParams    = @()
            
            # Параметры по энкодерам
            EncoderParams = @{
                x265               = @{
                    Quality  = 23
                    Preset   = 'slower'
                    BaseArgs = @(
                        '--output-depth', '10',
                        '--tune', 'grain',
                        '--no-strong-intra-smoothing',
                        '--rc-lookahead', '60',
                        '--aq-strength', '0.85',
                        '--aq-mode', '3',
                        '--psy-rd', '1.0',
                        '--psy-rdoq', '1.0',
                        '--deblock', '-1,-1',
                        '--qg-size', '64',
                        '--no-sao',
                        '--bframes', '8',
                        '--ref', '5',
                        '--b-adapt', '2',
                        '--range', 'limited',
                        '--colorprim', 'bt709',
                        '--transfer', 'bt709',
                        '--colormatrix', 'bt709'
                    )
                    # DeepSeek параметры
                    <#                     $BaseArgs = @(
                        '--tune', 'grain',              # КРИТИЧЕСКИ важно для пленки!
                        '--output-depth', '10',

                        # Motion estimation улучшения
                        '--me', 'star',                 # Лучше чем umh для grain
                        '--merange', '44',              # Оптимально для 1080p
                        '--subme', '6',                 # Точнее оценка движения
                        '--max-merge', '5',

                        # Adaptive Quantization
                        '--aq-mode', '3',               # Уже хорошо
                        '--aq-strength', '0.90',        # Чуть выше для grain
                        '--cbqpoffs', '-2',             # Смещение для chroma
                        '--crqpoffs', '-2',

                        # Psychovisual оптимизации
                        '--psy-rd', '1.2',              # Чуть выше для деталей
                        '--psy-rdoq', '2.0',            # Важно для сохранения текстуры

                        # Блок структура
                        '--ctu', '32',                  # Лучше для grain чем 64
                        '--qg-size', '32',              # 64 слишком большой для деталей
                        '--limit-tu', '4',              # Ограничить TU глубину
                        '--max-tu-size', '16',          # Для сохранения мелких деталей
                        '--tu-intra-depth', '4',
                        '--tu-inter-depth', '4',

                        # Deblocking & SAO
                        '--deblock', '-2:-2',           # Еще мягче для пленки
                        '--no-sao',                     # Правильно - отключаем!
                        '--selective-sao', '0',

                        # B-frames и предсказание
                        '--bframes', '6',               # 8 может быть избыточно
                        '--ref', '6',                   # Можно 6 если хватает памяти
                        '--b-intra',                    # Включить intra в B-фреймы
                        '--weightb',                    # Взвешенное предсказание
                        '--weightp',                    # Для P-фреймов тоже

                        # Rate control
                        '--rc-lookahead', '80',         # Увеличить для grain
                        '--scenecut', '45',             # Более чувствительный детектор сцен
                        '--scenecut-bias', '20',        # Смещение в сторону I-фреймов
                        '--no-open-gop',

                        # Дополнительные оптимизации
                        '--rd', '4',
                        '--rdoq-level', '2',
                        '--rect',
                        '--amp',
                        '--tskip',
                        '--tskip-fast',                 # Быстрый tskip режим
                        '--rd-refine',                  # Refine analysis

                        # Цвет и матрицы
                        '--range', 'limited',
                        '--colorprim', 'bt709',
                        '--transfer', 'bt709',
                        '--colormatrix', 'bt709',
                        '--chromaloc', '0',             # Авто chroma sample location

                        # Параллелизм
                        '--frame-threads', '4',         # 12 слишком много, лучше 4-6
                        '--wpp',                        # Wavefront все еще поддерживается
                        # Вместо pmode/pme используем:
                        '--no-early-skip',              # Более тщательный анализ
                        '--rdpenalty', '2'              # Penalty для skip modes
                    ) #>
                }
                SvtAv1Enc          = @{
                    Quality  = 25
                    Preset   = 3
                    BaseArgs = @('--rc', '0')
                }
                SvtAv1EncESS       = @{
                    Quality  = 'medium'     # 'higher', 'high', 'medium', 'low',  'lower'
                    Speed    = 'slow'       # 'slower', 'slow', 'medium', 'fast', 'faster'
                    BaseArgs = @(
                        '--rc', '0',
                        '--progress', '3',
                        '--auto-tiling', '0',
                        '--color-primaries', '1',
                        '--transfer-characteristics', '1',
                        '--matrix-coefficients', '1'
                    )
                }
                SvtAv1EncESS_grain = @{
                    Quality  = 'medium'     # 'higher', 'high', 'medium', 'low',  'lower'
                    Speed    = 'slow'   # 'slower', 'slow', 'medium', 'fast', 'faster'
                    BaseArgs = @(
                        '--rc', '0',
                        '--progress', '3',
                        '--auto-tiling', '0',
                        '--aq-mode', 2, '--scm', 0, '--film-grain-denoise', 0, '--film-grain', 12, '--enable-overlays', 1,
                        '--color-primaries', '1',
                        '--transfer-characteristics', '1',
                        '--matrix-coefficients', '1'
                    )
                }

                SvtAv1EncHDR       = @{
                    Quality  = 25
                    Preset   = 3
                    BaseArgs = @('--rc', '0')
                }
                SvtAv1EncPSYEX     = @{
                    Quality  = 25
                    Preset   = 3
                    BaseArgs = @('--rc', '0')
                }
                Rav1eEnc           = @{
                    Quality  = 80
                    Speed    = 4
                    BaseArgs = @()
                }
                AomAv1Enc          = @{
                    Quality  = 30
                    CpuUsed  = 6
                    BaseArgs = @('--end-usage=q')
                }
            }
        }
    }

    # Пути к шаблонам VapourSynth
    Templates  = @{
        VapourSynth = @{
            AutoCrop       = "Templates\AutoCropTemplate.py"
            MainScript     = "Templates\VapourSynth\MainScript.vpy"
            MainHDScript   = "Templates\VapourSynth\MainHDScript.vpy"
            HDRtoSDRScript = "Templates\VapourSynth\HDRtoSDRScript.vpy"
        }
    }
}


<#
& vspipe.exe -c y4m 'g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\Season_08\.av1\The.Walking.Dead.S08E01.tmp\The.Walking.Dead.S08E01.vpy' - | & 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\x265\x265.exe' --pools 12 --output-depth 10 --no-strong-intra-smoothing --aq-strength 0.85 --aq-mode 3 --psy-rd 1.0 --psy-rdoq 1.0 --deblock -1,-1 --qg-size 64 --no-sao --bframes 8 --ref 6 --b-adapt 2 --range limited --colorprim bt709 --transfer bt709 --colormatrix bt709 --crf 23 --preset slower --frames 67964 --output 'g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\Season_08\.av1\The.Walking.Dead.S08E01.tmp\The.Walking.Dead.S08E01.hevc' --input -

& 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\x265\x265.exe' --pools 12 --output-depth 10 --no-strong-intra-smoothing --aq-strength 0.85 --aq-mode 3 --psy-rd 1.0 --psy-rdoq 1.0 --deblock -1,-1 --qg-size 64 --no-sao --bframes 8 --ref 6 --b-adapt 2 --range limited --colorprim bt709 --transfer bt709 --colormatrix bt709 --crf 23 --preset slower --frames 67964 --output 'g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\Season_08\.av1\The.Walking.Dead.S08E01.tmp\The.Walking.Dead.S08E01.hevc' --input 'g:\Видео\Сериалы\Зарубежные\Ходячие мертвецы (Walking Dead)\Season_08\.av1\The.Walking.Dead.S08E01.tmp\The.Walking.Dead.S08E01.vpy'
#>