#
$raw = @('from	to
From.S03E01.Shatter.2160p.AMZN.WEB-D.H.265.RGzsRutracker	Извне - s03e01 - Надлом [2024-09-22]
From.S03E02.When.We.Go.2160p.AMZN.WEB-DL.H.265.RGzsRutracker	Извне - s03e02 - Когда мы уйдём [2024-09-29]
From.S03E03.Mouse.Trap.2160p.AMZN.WEB-DL.H.265.RGzsRutracker	Извне - s03e03 - Мышеловка [2024-10-06]
From.S03E04.There.and.Back.Again.2160p.AMZN.WEB-DL.H.265.RGzsRutracker	Извне - s03e04 - Туда и обратно [2024-10-13]
From.S03E05.The.Light.of.Day.2160p.AMZN.WEB-DL.H.265.RGzsRutracker	Извне - s03e05 - Свет дня [2024-10-20]
From.S03E06.Scar.Tissue.2160p.AMZN.WEB-DL.H.265.RGzsRutracker	Извне - s03e06 - Рубцовая ткань [2024-10-27]
')
$path = 'X:\temp\StaxRipTemp\Извне\season 03\'
$filterList = @('.ac3', '.eac3', '.srt', '.opus', '.aac', '.xml')
$extraFilter = "*"
$files = Get-ChildItem -LiteralPath $path -File -Recurse |
Where-Object {
            ($_.Extension -iin $filterList) -and
            ($_.BaseName -like $extraFilter)
}
Write-Host ("Найдено файлов: {0}" -f $files.Count) -ForegroundColor DarkGreen
$filenames = $raw | ConvertFrom-Csv -Delimiter "`t"

foreach ($f in $files) {
    $newFilename = $f.Name
    foreach ($nf in $filenames) {
        $newFilename = $newFilename.Replace($nf.from, $nf.to)
    }
    Write-Host $f -ForegroundColor DarkMagenta -NoNewline
    Write-Host " >>> " -ForegroundColor Blue -NoNewline
    Write-Host $newFilename -ForegroundColor DarkGreen
    $newFilename = Join-Path $f.DirectoryName -ChildPath $newFilename
    Rename-Item $f -NewName $newFilename # -WhatIf
}





function Create-Symlinks ([string]$strSourcePath, [string]$strDestPath) {
    $files = Get-ChildItem $strSourcePath -Recurse:$false -File:$true
    foreach ($f in $files) {
        $nn = ("Условный мент s05e{0:00}{1}" -f $f.BaseName.Substring(14,2), $f.Extension)
        $strNewFileName = Join-Path $strDestPath -ChildPath $nn #$f.Name
        Write-Host $f.FullName -ForegroundColor Blue
        Write-Host $strNewFileName -ForegroundColor DarkBlue
        New-Item -ItemType SymbolicLink -Path $strNewFileName -Target $f.FullName -Force:$false
        # Start-Sleep 10
    }
}

Create-Symlinks -strSourcePath 'v:\Сериалы\Отечественные\Условный мент\Uslovnyj.ment.WEB-DL.(1080p).lunkin\Uslovnyj ment.(5.sezon).WEB-DL.(1080p).lunkin\' `
                -strDestPath 'y:\.temp\Сериалы\Отечественные\Условный мент\сезон 05\'