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
    
    # Пути к шаблонам VapourSynth
    Templates  = @{
        VapourSynth = @{
            AutoCrop       = "Templates\AutoCropTemplate.py"
            MainScript     = "Templates\VapourSynth\MainScript.vpy"
            MainHDScript   = "Templates\VapourSynth\MainHDScript.vpy"
            HDRtoSDRScript = "Templates\VapourSynth\HDRtoSDRScript.vpy"
        }
    }
    
    # Параметры обработки
    Processing = @{
        # DefaultThreads     = 10
        keepTempAudioFiles = $false
        DeleteTempFiles    = $true
        AutoCropThreshold  = 1000
        TempDir            = "r:\Temp\"
        VSPipeMethod       = "vspipe"  # Возможные значения: "vspipe", "ffmpeg"
        CalculateVMAF      = $false    # Рассчитывать VMAF после кодирования
    }
    
    Encoding   = @{
        # КОДЫ ЭНКОДЕРОВ для использования в именах файлов
        EncoderCodes = @{
            x265           = 'hevc'
            SvtAv1Enc      = 'av1'
            SvtAv1EncESS   = 'av1'
            SvtAv1EncHDR   = 'av1'
            SvtAv1EncPSYEX = 'av1'
            Rav1eEnc       = 'av1'
            AomAv1Enc      = 'av1'
        }
        
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
        DefaultEncoder    = 'x265.film_grain'
        
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
            
            # ИЕРАРХИЧЕСКАЯ СТРУКТУРА ПРЕСЕТОВ
            EncoderPresets = @{
                # ============================================
                # HEVC (x265) ПРЕСЕТЫ
                # ============================================
                x265 = @{
                    main = @{
                        DisplayName = "x265 Main Preset"
                        CodecCode   = 'hevc'
                        Quality     = 23
                        Preset      = 'slower'
                        BaseArgs    = @(
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
                    }
                    
                    film_grain = @{
                        DisplayName = "x265 Film Grain Optimized"
                        CodecCode   = 'hevc'
                        Quality     = 24
                        Preset      = 'slower'
<# Main@L5
                        BaseArgs    = @(
                            '--output-depth', '10',
                            '--tune', 'grain',
                            '--no-strong-intra-smoothing',
                            '--rc-lookahead', '80',
                            '--aq-strength', '0.90',
                            '--aq-mode', '3',
                            '--psy-rd', '1.2',
                            '--psy-rdoq', '2.0',
                            '--deblock', '-2:-2',
                            '--qg-size', '32',
                            '--no-sao',
                            '--bframes', '8',
                            '--ref', '6',
                            '--b-adapt', '2',
                            '--range', 'limited',
                            '--colorprim', 'bt709',
                            '--transfer', 'bt709',
                            '--colormatrix', 'bt709',
                            '--ctu', '32'
                        )
#>
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
                    }
                    
                    fast = @{
                        DisplayName = "x265 Fast Preset"
                        CodecCode   = 'hevc'
                        Quality     = 25
                        Preset      = 'medium'
                        BaseArgs    = @(
                            '--output-depth', '10',
                            '--tune', 'grain',
                            '--rc-lookahead', '40',
                            '--aq-strength', '0.80',
                            '--aq-mode', '3',
                            '--psy-rd', '0.8',
                            '--psy-rdoq', '0.8',
                            '--deblock', '-1,-1',
                            '--qg-size', '64',
                            '--no-sao',
                            '--bframes', '6',
                            '--ref', '4',
                            '--b-adapt', '2'
                        )
                    }
                }
                
                # ============================================
                # AV1 (SVT-AV1) ПРЕСЕТЫ
                # ============================================
                SvtAv1Enc = @{
                    main = @{
                        DisplayName = "SVT-AV1 Main Preset"
                        CodecCode   = 'av1'
                        Quality     = 25
                        Preset      = 3
                        BaseArgs    = @('--rc', '0')
                    }
                    
                    fast = @{
                        DisplayName = "SVT-AV1 Fast Preset"
                        CodecCode   = 'av1'
                        Quality     = 30
                        Preset      = 6
                        BaseArgs    = @('--rc', '0')
                    }
                    
                    slow = @{
                        DisplayName = "SVT-AV1 Slow Preset"
                        CodecCode   = 'av1'
                        Quality     = 22
                        Preset      = 2
                        BaseArgs    = @('--rc', '0')
                    }
                }
                
                SvtAv1EncESS = @{
                    quality_optimized = @{
                        DisplayName = "SVT-AV1 ESS Quality Optimized"
                        CodecCode   = 'av1'
                        Quality     = 'higher'
                        Speed       = 'slower'
                        BaseArgs    = @(
                            '--rc', '0',
                            '--progress', '3',
                            '--auto-tiling', '0',
                            '--color-primaries', '1',
                            '--transfer-characteristics', '1',
                            '--matrix-coefficients', '1'
                        )
                    }
                    
                    balanced = @{
                        DisplayName = "SVT-AV1 ESS Balanced"
                        CodecCode   = 'av1'
                        Quality     = 'medium'
                        Speed       = 'slow'
                        BaseArgs    = @(
                            '--rc', '0',
                            '--progress', '3',
                            '--auto-tiling', '0',
                            '--color-primaries', '1',
                            '--transfer-characteristics', '1',
                            '--matrix-coefficients', '1'
                        )
                    }
                    
                    grain_optimized = @{
                        DisplayName = "SVT-AV1 ESS Film Grain"
                        CodecCode   = 'av1'
                        Quality     = 'medium'
                        Speed       = 'slow'
                        BaseArgs    = @(
                            '--rc', '0',
                            '--progress', '3',
                            '--auto-tiling', '0',
                            '--aq-mode', '2',
                            '--scm', '0',
                            '--film-grain-denoise', '0',
                            '--film-grain', '12',
                            '--enable-overlays', '1',
                            '--color-primaries', '1',
                            '--transfer-characteristics', '1',
                            '--matrix-coefficients', '1'
                        )
                    }
                    
                    fast = @{
                        DisplayName = "SVT-AV1 ESS Fast"
                        CodecCode   = 'av1'
                        Quality     = 'low'
                        Speed       = 'fast'
                        BaseArgs    = @(
                            '--rc', '0',
                            '--progress', '3',
                            '--auto-tiling', '1',
                            '--color-primaries', '1',
                            '--transfer-characteristics', '1',
                            '--matrix-coefficients', '1'
                        )
                    }
                }
                
                SvtAv1EncHDR = @{
                    main = @{
                        DisplayName = "SVT-AV1 HDR Main Preset"
                        CodecCode   = 'av1'
                        Quality     = 25
                        Preset      = 3
                        BaseArgs    = @('--rc', '0')
                    }
                }
                
                SvtAv1EncPSYEX = @{
                    main = @{
                        DisplayName = "SVT-AV1 PSYEX Main Preset"
                        CodecCode   = 'av1'
                        Quality     = 25
                        Preset      = 3
                        BaseArgs    = @('--rc', '0')
                    }
                }
                
                # ============================================
                # ДРУГИЕ AV1 ЭНКОДЕРЫ
                # ============================================
                Rav1eEnc = @{
                    main = @{
                        DisplayName = "Rav1e Main Preset"
                        CodecCode   = 'av1'
                        Quality     = 80
                        Speed       = 4
                        BaseArgs    = @()
                    }
                    
                    fast = @{
                        DisplayName = "Rav1e Fast Preset"
                        CodecCode   = 'av1'
                        Quality     = 90
                        Speed       = 8
                        BaseArgs    = @()
                    }
                }
                
                AomAv1Enc = @{
                    main = @{
                        DisplayName = "AOM AV1 Main"
                        CodecCode   = 'av1'
                        Quality     = 30
                        CpuUsed     = 6
                        BaseArgs    = @('--end-usage=q')
                    }
                    
                    fast = @{
                        DisplayName = "AOM AV1 Fast"
                        CodecCode   = 'av1'
                        Quality     = 35
                        CpuUsed     = 8
                        BaseArgs    = @('--end-usage=q')
                    }
                }
            }
        }
    }
}