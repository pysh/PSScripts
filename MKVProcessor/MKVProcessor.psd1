@{
    RootModule = 'MKVProcessor.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Paul'
    CompanyName = 'Private'
    Copyright = '(c) 2025. All rights reserved.'
    Description = 'PowerShell module for MKV file processing with frame rate conversion and tag cleaning'
    PowerShellVersion = '7.5'
    RequiredModules = @()
    FunctionsToExport = @(
        'Invoke-MKVRemux',
        'Start-BatchMKVRemux', 
        'Get-MKVGuestName',
        'New-MKVDescription',
        'Clear-TagText',
        'Export-CleanedMKVTags'
    )
    CmdletsToExport = @()
    VariablesToExport = ''
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('MKV', 'Video', 'Remux', 'Tags')
            LicenseUri = ''
            ProjectUri = ''
            ReleaseNotes = 'Initial version'
        }
    }
}