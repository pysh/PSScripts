
function Get-Currency {
    param (
        [string]$prm
    )

    $baseUrl = 'https://api.coingecko.com/api/v3/'
    $url = ($baseUrl, '/simple/price?ids=bitcoin,gridcoin-research&vs_currencies=usd,rub' -join '')
    Write-Host $url -ForegroundColor DarkGreen -NoNewline
    $req = Invoke-WebRequest -Uri $url -Method Get
    if ($req.StatusCode -eq 200) {
        $content = $req.Content
        $parsed = ConvertFrom-Json $content
        $parsed | Format-List
    }
}


$filePath = (Get-ChildItem 'X:\Apps\_VideoEncoding\av1an\logs\' -File) | Sort-Object CreationTime -Top 2 -Descending | Sort-Object -Top 1