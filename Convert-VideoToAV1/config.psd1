@{
    # Пути к инструментам
    Tools = @{
        FFmpeg     = "ffmpeg.exe"
        FFprobe    = "ffprobe.exe"
        MkvMerge   = "mkvmerge.exe"
        MkvExtract = "mkvextract.exe"
        MkvPropedit= "mkvpropedit.exe"
        VSPipe     = "vspipe.exe"
        #SvtAv1Enc  = "X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
        SvtAv1Enc       = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp\SvtAv1EncApp.exe'
        SvtAv1EncESS    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-Essential\SvtAv1EncApp.exe'
        SvtAv1EncHDR    = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-HDR\SvtAv1EncApp.exe'
        SvtAv1EncPSYEX  = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Encoders\SvtAv1EncApp-PSYEX\SvtAv1EncApp.exe'
        OpusEnc         = 'd:\Sources\media-autobuild_suite\local64\bin-audio\opusenc.exe'
        AutoCrop        = 'X:\Apps\_VideoEncoding\StaxRip\Apps\Support\AutoCrop\AutoCrop.exe'
    }

    # Параметры обработки
    Processing = @{
        DefaultThreads = 4
        keepTempAudioFiles = $true
        DeleteTempFiles = $false
        AutoCropThreshold = 1000
        TempDir = "r:\Temp\"
    }
    
    Encoding = @{
        Encoder = Tools.SvtAv1EncESS
        Video = @{
            CRF = 25
            Preset = 3
            CropRound = 2
            XtraParams = @()
        }
        Audio = @{
            CopyAudio = $false
            Bitrates = @{
                Stereo = "192k"
                Surround = "340k"
                Multi = "256k"
            }
        }
    }

    Templates = @{
        VapourSynth = @{
            AutoCrop = 'd:\PSScripts\Convert-VideoToAV1\Templates\AutoCropTemplate.py'
        }
    }
}