<#
function Verb-Noun {
    [CmdletBinding()]
    param (
        
    )
    
    begin {
        
    }
    
    process {
        
    }
    
    end {
        
    }
}



function FunctionName (OptionalParameters) {
    
}
#>

. 'D:\Sources\PSScripts\Function_Invoke-Process.ps1'

function Get-ScenesFromVideo {
    param (
        [PSDefaultValue(Help = 'Input file name', Value = 'qqq')]
        [string]$inputFileName,

        [PSDefaultValue(Help = 'Split-Path -Path $inputFileName', Value = 'Split-Path -Path $inputFileName' )]
        [string]$outputDir = (Split-Path -Path $inputFileName)
    )
    # $tmpDir = $env:TEMP
    # $outputDir = $tmpDir
    $sceneDetectFileName = 'scenedetect.exe'
    $scenesFileName = ('{0}-Scenes.csv' -f (Split-Path -Path $inputFileName -LeafBase))
    $scenesFile = Join-Path $outputDir -ChildPath $scenesFileName
    if (Test-Path ([Management.Automation.WildcardPattern]::Escape($scenesFile))) { Remove-Item $scenesFile -Force }
    $prm = @(
        ('--input "{0}"' -f $inputFileName)
        '--frame-skip 11', '--quiet',
        'list-scenes',
        ('--output "{0}"' -f $outputDir),
        ('--filename "{0}"' -f $scenesFileName),
        '--skip-cuts'
    )
    Write-Host $sceneDetectFileName ($prm -f ' ') -ForegroundColor DarkBlue
    $proc = Invoke-Process -commandPath $sceneDetectFileName -commandArguments ($prm -join ' ')
    if ($proc.ExitCode -eq 0) {
        $scenes = Import-Csv -Path ([Management.Automation.WildcardPattern]::Escape($scenesFile)) -Delimiter ',' -Encoding utf8
        Write-Host 'OK', $proc.stdout -ForegroundColor Green
    } else {
        Write-Host 'ERROR', $proc.stderr -ForegroundColor Red
    }
    return $scenes
}

Clear-Host
$sc = Get-ScenesFromVideo -inputFileName 'y:\.temp\YT_y\Слава Никифоров. Стероидный Самурай из Казахстана ｜ StandUp PATRIKI [u5ZENcdjSGc].mkv'
Write-Host 'Detected scenes: ' $sc.Count -ForegroundColor DarkGreen
