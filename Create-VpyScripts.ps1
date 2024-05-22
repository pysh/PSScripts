$d = 'X:\temp\InspectorGavrilov\'
$files = Get-ChildItem -LiteralPath $d -File | Where-Object ({$_.Extension -iin '.mkv'})
$files.Count
foreach ($f in $files) {
    $cmd = @(
        'from vapoursynth import core'
        'core.max_cache_size=1024'
        ('clip = core.lsmas.LWLibavSource(r"{0}", cachefile=r"{1}")' -f $f.FullName, ([System.IO.Path]::ChangeExtension($f, '.lwi')))
        'clip = core.std.CropRel(clip, left=0, top=276, right=0, bottom=276)'
        'clip.set_output()'
    )
    $cmd | Out-File -FilePath ([System.IO.Path]::ChangeExtension($f, '.vpy')) -Encoding utf8 -Force
}


