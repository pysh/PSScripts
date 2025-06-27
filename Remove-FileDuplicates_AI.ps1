function Remove-FileDuplicates {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Medium')]
    param(
        [Parameter(Mandatory=$false)]
        [string]$Path='X:\temp2\xuk\',
        
        [switch]$Recurse,
        
        [ValidateSet("Default", "LongestPath", "AlphabeticalName", "ShortestName")]
        [string]$Priority = "AlphabeticalName",
        
        [string]$CacheDatabase = "X:\temp2\FileDuplicatesCache.db"
    )

    # Проверяем и устанавливаем модуль PSSQLite
    if (-not (Get-Module -Name "PSSQLite" -ListAvailable)) {
        Write-Host "Installing PSSQLite module..." -ForegroundColor Yellow
        Install-Module -Name "PSSQLite" -Force -Scope CurrentUser -ErrorAction Stop
    }
    Import-Module PSSQLite -Force

    # Проверка существования директории
    if (-not (Test-Path -Path $Path -PathType Container)) {
        Write-Error "Directory does not exist: $Path"
        return
    }

    # Подключение к SQLite
    $dbConnection = New-SQLiteConnection -DataSource $CacheDatabase

    # Создание таблицы (если не существует)
    Invoke-SqliteQuery -SQLiteConnection $dbConnection -Query @"
    CREATE TABLE IF NOT EXISTS FileHashes (
        FilePath TEXT PRIMARY KEY,
        FileSize INTEGER,
        LastWriteTime TEXT,
        MD5Hash TEXT
    );
"@

    # Получаем все файлы
    $allFiles = @(Get-ChildItem -Path $Path -File -Recurse:$Recurse)
    Write-Host "Found $($allFiles.Count) files for processing" -ForegroundColor Cyan

    $totalDeleted = 0
    $totalSpace = 0

    # Прогресс-бар для обработки файлов
    Write-Progress -Activity "Кеширование файлов" -Status "Подготовка..."
    $fileCounter = 0

    foreach ($file in $allFiles) {
        $fileCounter++
        $percentComplete = ($fileCounter / $allFiles.Count) * 100
        
        Write-Progress -Activity "Кеширование файлов" -Status "Обработка файла $fileCounter из $($allFiles.Count)" `
            -CurrentOperation $file.FullName -PercentComplete $percentComplete

        # Проверяем кеш
        $cachedFile = Invoke-SqliteQuery -SQLiteConnection $dbConnection `
            -Query "SELECT * FROM FileHashes WHERE FilePath = @filePath" `
            -SqlParameters @{ filePath = $file.FullName }

        # Если файла нет в кеше или он изменился
        if (-not $cachedFile -or [datetime]$cachedFile.LastWriteTime -ne $file.LastWriteTime) {
            $md5Hash = (Get-FileHash -Path $file.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash
            
            if ($md5Hash) {
                Invoke-SqliteQuery -SQLiteConnection $dbConnection `
                    -Query @"
                    INSERT OR REPLACE INTO FileHashes 
                        (FilePath, FileSize, LastWriteTime, MD5Hash)
                    VALUES 
                        (@filePath, @fileSize, @lastWriteTime, @md5Hash)
"@ `
                    -SqlParameters @{
                        filePath = $file.FullName
                        fileSize = $file.Length
                        lastWriteTime = $file.LastWriteTime.ToString("o")
                        md5Hash = $md5Hash
                    }
            }
        }
    }
    Write-Progress -Activity "Кеширование файлов" -Completed

    # Получаем группы дубликатов
    $duplicateGroups = @(Invoke-SqliteQuery -SQLiteConnection $dbConnection `
        -Query @"
        SELECT MD5Hash, COUNT(*) as Count, GROUP_CONCAT(FilePath, '|') as Files
        FROM FileHashes
        GROUP BY MD5Hash
        HAVING COUNT(*) > 1
"@)

    # Прогресс-бар для обработки дубликатов
    Write-Progress -Activity "Обработка дубликатов" -Status "Подготовка..."
    $groupCounter = 0

    foreach ($group in $duplicateGroups) {
        $groupCounter++
        $percentComplete = ($groupCounter / $duplicateGroups.Count) * 100
        
        Write-Progress -Activity "Обработка дубликатов" `
            -Status "Группа $groupCounter из $($duplicateGroups.Count) ($($group.Count) файлов)" `
            -PercentComplete $percentComplete

        $filePaths = $group.Files -split '\|'
        $files = $filePaths | ForEach-Object { Get-Item $_ }

        # Сортировка по выбранному критерию
        switch ($Priority) {
            "LongestPath" { $sortedFiles = $files | Sort-Object { $_.FullName.Length }, LastWriteTime }
            "AlphabeticalName" { $sortedFiles = $files | Sort-Object Name, LastWriteTime }
            "ShortestName" { $sortedFiles = $files | Sort-Object { $_.Name.Length }, LastWriteTime }
            Default { $sortedFiles = $files | Sort-Object LastWriteTime }
        }

        $filesToDelete = $sortedFiles | Select-Object -SkipLast 1

        foreach ($file in $filesToDelete) {
            if ($PSCmdlet.ShouldProcess($file.FullName, "Delete duplicate file")) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Host "DELETED: $($file.FullName)" -ForegroundColor Red
                    $totalDeleted++
                    $totalSpace += $file.Length

                    # Удаляем запись из кеша
                    Invoke-SqliteQuery -SQLiteConnection $dbConnection `
                        -Query "DELETE FROM FileHashes WHERE FilePath = @filePath" `
                        -SqlParameters @{ filePath = $file.FullName }
                }
                catch {
                    Write-Warning "Failed to delete $($file.FullName): $_"
                }
            }
        }
    }
    Write-Progress -Activity "Обработка дубликатов" -Completed

    $dbConnection.Close()

    # Формирование отчета
    $report = [PSCustomObject]@{
        TotalFilesProcessed = $allFiles.Count
        DuplicateGroupsFound = $duplicateGroups.Count
        DeletedFiles = $totalDeleted
        SpaceFreedMB = [math]::Round($totalSpace / 1MB, 2)
        CacheLocation = $CacheDatabase
    }

    Write-Host "`n=== Duplicate Cleanup Report ===" -ForegroundColor Green
    $report | Format-List | Out-String | Write-Host

    return $report
}