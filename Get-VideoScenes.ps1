function Get-ScenesFromVideo {
    param (
        [string]$videoFileName
    )
    $sceneDetectFileName = 'scenedetect.exe'
    $prm = @(
            ('--input "{0}"' -f $videoFileName)
            ('--stats "{0}"' -f ($videoFileName + '.scenes'))
            ('detect-content')
            ('list-scenes --quiet')
    )
    Write-Host ($prm -join "`r`n") -ForegroundColor DarkCyan
}

Get-ScenesFromVideo -videoFileName 'v:\ТВ передачи\История на миллион\История на миллион.2024.WEB-DL 1080p.Files-x\05. История на миллион.2024.WEB-DL 1080p.Files-x.mkv'