@{
    # Пути к инструментам
    Tools = @{
        FFmpeg     = "ffmpeg.exe"
        FFprobe    = "ffprobe.exe"
        MkvMerge   = "mkvmerge.exe"
        MkvExtract = "mkvextract.exe"
        MkvPropedit= "mkvpropedit.exe"
        VSPipe     = "vspipe.exe"
        #SvtAv1Enc  = "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe"
        SvtAv1Enc  = "d:\Sources\media-autobuild_suite\local64\bin-video\SvtAv1EncApp.exe"
        OpusEnc    = "d:\Sources\media-autobuild_suite\local64\bin-audio\opusenc.exe"
        AutoCrop   = "X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe"
    }

    # Параметры обработки
    Processing = @{
        DefaultThreads       = 20
        #TempDir              = ".\temp"
        DeleteTempFiles      = $false
        DeleteTempAudioFiles = $false
        AutoCropThreshold    = 1000
    }

    # Параметры кодирования
    Encoding = @{
        Video = @{
            CRF         = 31
            Preset      = 3
            CropRound   = 2
            XtraParams = @()
        }
        Audio = @{
            Bitrates     = @{
                Stereo   = 192
                Surround = 340
                Multi    = 384
            }
        }
    }

    # Шаблоны
    Templates = @{
        VapourSynth = @{
            AutoCrop   = "d:\PSScripts\Convert-VideoToAV1\Templates\AutoCropTemplate.py"
            Encoding   = "EncodingTemplate.vpy"
        }
    }
}