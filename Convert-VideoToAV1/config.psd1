@{
    # Пути к инструментам
    Tools = @{
        FFmpeg     = "ffmpeg.exe"
        FFprobe    = "ffprobe.exe"
        MkvMerge   = "mkvmerge.exe"
        MkvExtract = "mkvextract.exe"
        MkvPropedit= "mkvpropedit.exe"
        VSPipe     = "vspipe.exe"
        x265       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\x265\x265.exe'
        SvtAv1Enc       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
        # SvtAv1EncESS    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-Essential\SvtAv1EncApp.exe'
        SvtAv1EncESS    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-Essential\SvtAv1EncApp_official.exe'
        SvtAv1EncHDR    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-HDR\SvtAv1EncApp.exe'
        SvtAv1EncPSYEX  = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-PSYEX\SvtAv1EncApp.exe'
        Rav1eEnc        = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\rav1e\rav1e.exe'
        AomAv1Enc       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\AOMEnc\aomenc.exe'
        OpusEnc         = 'd:\Sources\media-autobuild_suite\local64\bin-audio\opusenc.exe'
        AutoCrop        = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe'
    }

    # Параметры обработки
    Processing = @{
        DefaultThreads = 10
        keepTempAudioFiles = $false
        DeleteTempFiles = $false
        AutoCropThreshold = 1000
        TempDir = "r:\Temp\"
        VSPipeMethod = "vspipe"  # Возможные значения: "vspipe", "ffmpeg"
    }
    
    Encoding = @{
        # Доступные энкодеры
        AvailableEncoders = @{
            SvtAv1Enc      = 'Tools.SvtAv1Enc'
            SvtAv1EncESS   = 'Tools.SvtAv1EncESS'
            SvtAv1EncHDR   = 'Tools.SvtAv1EncHDR'
            SvtAv1EncPSYEX = 'Tools.SvtAv1EncPSYEX'
            Rav1eEnc       = 'Tools.Rav1eEnc'
            AomAv1Enc      = 'Tools.AomAv1Enc'
            x265           = 'Tools.x265'
        }
        
        # Энкодер по умолчанию
        DefaultEncoder = 'SvtAv1EncESS'
        
        Video = @{
            CopyVideo = $true
            CropRound = 2
            XtraParams = @()
            
            # Параметры по энкодерам
            EncoderParams = @{
                x265 = @{
                    Quality = 23
                    Preset = 'slower'
                    BaseArgs = @('--output-depth', '10',
                        '--no-strong-intra-smoothing',
                        '--constrained-intra',
                        '--range', 'limited',
                        '--colorprim', 'bt709',
                        '--transfer', 'bt709',
                        '--colormatrix', 'bt709'
                        )
                }
                SvtAv1Enc = @{
                    Quality = 25
                    Preset = 3
                    BaseArgs = @('--rc', '0')
                }
                SvtAv1EncESS = @{
                    Speed    = 'slow' # Available speeds are: slower, slow, medium, fast, faster. Default is slow.
                    Quality  = 'lower'  # Available qualities are: higher, high, medium, low, lower. Default is medium.
                    BaseArgs = @(
                        '--rc', '0'
                        '--progress', '3',
                        '--auto-tiling', '0'
                        '--color-primaries', '1',
                        '--transfer-characteristics', '1',
                        '--matrix-coefficients', '1'
                    )
                }
                SvtAv1EncHDR = @{
                    Quality = 25
                    Preset = 3
                    BaseArgs = @('--rc', '0') #, '--enable-hdr', '1')
                }
                SvtAv1EncPSYEX = @{
                    Quality = 25
                    Preset = 3
                    BaseArgs = @('--rc', '0') #, '--enable-psy-ex', '1')
                }
                Rav1eEnc = @{
                    Quality = 80
                    Speed = 4
                    BaseArgs = @()
                }
                AomAv1Enc = @{
                    Quality = 30
                    CpuUsed = 6
                    BaseArgs = @('--end-usage=q')
                }
            }
        }
        Audio = @{
            CopyAudio = $false
            Bitrates = @{
                Stereo   = "200k"
                Surround = "384k"
                Multi    = "480k"
            }
        }
    }

    VPSSources = @{
        Video = @{
            LSMASH     = 'clip = core.lsmas.LibavSMASHSource(r"{%VideoPath%}")'
            LWLib      = 'clip = core.lsmas.LWLibavSource(source=r"{%VideoPath%}", cachefile=r"{%CacheFile%}", decoder="cuda")'
            BestSource = 'clip = core.best.VideoSource(source=r"{%VideoPath%}", track=-1, fpsnum=-1, fpsden=1, rff=False, threads=0, seekpreroll=20, enable_drefs=False, use_absolute_path=False, cachemode=3, cachepath=r"{%CacheFile%}", cachesize=1000, hwdevice="cuda", extrahwframes=9, showprogress=1)'
        }
        Audio = @{
            FFmpeg = 'FFmpeg'
        }
    }

    Templates = @{
        VapourSynth = @{
            AutoCrop = 'd:\PSScripts\Convert-VideoToAV1\Templates\AutoCropTemplate.py'
            MainScript = @'
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"{%VideoPath%}", cachefile=r"{%CacheFile%}")
{%trimScript%}

clip = core.resize.Spline36(clip, format=vs.YUV444PS)
ref  = core.bm3dcuda.BM3D(clip, sigma=[5, 0, 0])
clip = core.bm3dcuda.BM3D(clip, ref, sigma=[5, 0, 0])
clip = core.resize.Spline36(clip, format=vs.YUV420P16)
clip = core.placebo.Shader(clip, shader=r"X:\Apps\_VideoEncoding\ffmpeg\LiftGammaGain_qwen_lite.glsl")
clip = core.resize.Spline36(clip, format=vs.YUV420P10, dither_type="error_diffusion")

#clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, {%CropParams.Left%}, {%CropParams.Right%}, {%CropParams.Top%}, {%CropParams.Bottom%})
clip.set_output()
'@
            MainHDScript = @'
import vapoursynth as vs
core = vs.core
clip = core.lsmas.LWLibavSource(source=r"{%VideoPath%}", cachefile=r"{%CacheFile%}")
{%trimScript%}

clip = core.resize.Spline36(clip, format=vs.YUV420P16)
clip = core.placebo.Shader(clip, shader=r"X:\Apps\_VideoEncoding\ffmpeg\LiftGammaGain_qwen_lite.glsl")
clip = core.placebo.Shader(clip, shader=r"X:\Apps\_VideoEncoding\ffmpeg\adaptive-sharpen.glsl")
clip = core.resize.Spline36(clip, format=vs.YUV420P10, dither_type="error_diffusion")

#clip = core.fmtc.bitdepth(clip, bits=10)
clip = core.std.Crop(clip, {%CropParams.Left%}, {%CropParams.Right%}, {%CropParams.Top%}, {%CropParams.Bottom%})
clip.set_output()
'@
            HDRtoSDRScript = @'
import os, sys
import vapoursynth as vs
from vapoursynth import core

sys.path.append(r"X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\VS\Scripts")
import importlib.machinery

havsfunc = importlib.machinery.SourceFileLoader('havsfunc', r"X:\Apps\_VideoEncoding\StaxRip\Apps\Plugins\VS\Scripts\havsfunc.py").load_module()


# Цветовые пространства (src_csp, dst_csp)
CSP_SDR   = 0
CSP_HDR10 = 1
CSP_HLG   = 2
CSP_DOVI  = 3

# Цветовые первичные (dst_prim)
PRIMARY_UNKNOWN   = 0
PRIMARY_BT601_525 = 1
PRIMARY_BT601_625 = 2
PRIMARY_BT709     = 3
PRIMARY_BT470M    = 4
PRIMARY_EBU       = 5
PRIMARY_BT2020    = 6
PRIMARY_APPLE     = 7
PRIMARY_ADOBE     = 8
PRIMARY_PROPHOTO  = 9
PRIMARY_CIE1931   = 10
PRIMARY_DCIP3     = 11
PRIMARY_DCIP3_D65 = 12
PRIMARY_VGAMUT    = 13
PRIMARY_SGAMUT    = 14
PRIMARY_FILM_C    = 15
PRIMARY_ACES_0    = 16
PRIMARY_ACES_1    = 17

# Функции тонмаппинга (tone_mapping_function)
TONE_CLIP            = 0
TONE_MAP_SPLINE      = 1 # default
TONE_MAP_ST2094_40   = 2
TONE_MAP_ST2094_10   = 3
TONE_MAP_BT2390      = 4
TONE_MAP_BT2446A     = 5
TONE_MAP_REINHARD    = 6
TONE_MAP_MOBIUS      = 7
TONE_MAP_HABLE       = 8
TONE_MAP_GAMMA       = 9
TONE_MAP_LINEAR      = 10
TONE_MAP_LINEARLIGHT = 11

# Режимы отображения гамута (gamut_mapping)
GAMUT_MAP_CLIP       = 0
GAMUT_MAP_PERCEPTUAL = 1 # default
GAMUT_MAP_SOFTCLIP   = 2
GAMUT_MAP_RELATIVE   = 3
GAMUT_MAP_SATURATION = 4
GAMUT_MAP_ABSOLUTE   = 5
GAMUT_MAP_DESATURE   = 6
GAMUT_MAP_DARKEN     = 7
GAMUT_MAP_HIGHLIGHT  = 8
GAMUT_MAP_LINEAR     = 9


# Метаданные (metadata)
METADATA_AUTO      = 0 #default
METADATA_NONE      = 1
METADATA_HDR10     = 2
METADATA_HDR10PLUS = 3
METADATA_LUMINANCE = 4

# Загрузка видео
clip = core.lsmas.LWLibavSource(source=r"{%VideoPath%}", cachefile=r"{%CacheFile%}") #, prefer_hw=4)
#clip = core.bs.VideoSource(r"{%VideoPath%}", track=-1, fpsnum=-1, fpsden=1, rff=False, threads=0, seekpreroll=20, enable_drefs=False, use_absolute_path=False, cachemode=3, cachepath=r"{%CacheFile%}", cachesize=1000, hwdevice="cuda", extrahwframes=9, showprogress=1)
{%trimScript%}

# Повышаем битность для точных вычислений
clip = core.fmtc.bitdepth(clip, bits=16)

clip = core.placebo.Tonemap(
   clip,
   src_csp=CSP_HDR10,
   dst_csp=CSP_SDR,
   dst_prim=PRIMARY_BT709,
   metadata=METADATA_AUTO,
   src_min=0.005,
   src_max=1000.0,
   dst_min=0.0,
   dst_max=60.0,
   dynamic_peak_detection=True,
   tone_mapping_function=TONE_MAP_SPLINE,
   tone_mapping_param=0.0,
   gamut_mapping=GAMUT_MAP_PERCEPTUAL,
   percentile=99.9,
   contrast_recovery=1
)

# Дебанинг и резкость
clip = core.neo_f3kdb.Deband(clip, preset="veryhigh")
clip = havsfunc.LSFmod(clip, defaults='slow', strength=50, Smode=5, Smethod=3, kernel=11,
                        secure=True, Szrp= 16, Spwr= 4, SdmpLo= 4, SdmpHi= 48, Lmode=4, overshoot=1, undershoot=1,
                        soft=-2, soothe=True, keep=20, edgemode=0, edgemaskHQ=True, ss_x= 1.50, ss_y=1.50)

# Конвертируем обратно в YUV для кодирования
clip = core.resize.Spline36(clip, format=vs.YUV420P10, matrix_s="709")

# Обрезка
clip = core.std.Crop(clip, {%CropParams.Left%}, {%CropParams.Right%}, {%CropParams.Top%}, {%CropParams.Bottom%})
#clip = core.std.Crop(clip, 0, 0, 276, 276)

# Экспорт
clip.set_output()
'@
        }
    }
}