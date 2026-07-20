[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\grill-powers'),
    [string]$DiscoveryRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.agents\skills')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Get-PathItem {
    param([Parameter(Mandatory = $true)][string]$Path)

    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Assert-File {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Missing $Label`: $Path"
    }
}

function Assert-Directory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Missing $Label`: $Path"
    }
}

function Assert-StringEqual {
    param(
        [Parameter(Mandatory = $true)][string]$Actual,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if (-not $Actual.Equals($Expected, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label mismatch. Expected $Expected; found $Actual"
    }
}

function Assert-JunctionTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget
    )

    $item = Get-PathItem -Path $Path
    if ($null -eq $item) {
        throw "Missing junction: $Path"
    }
    if (-not ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
        throw "Expected a directory junction: $Path"
    }

    $targets = @($item.Target)
    if ($targets.Count -ne 1) {
        throw "Expected one junction target at $Path; found $($targets.Count)"
    }

    $actual = Resolve-FullPath -Path ([string]$targets[0])
    $expected = Resolve-FullPath -Path $ExpectedTarget
    Assert-StringEqual -Actual $actual -Expected $expected -Label "Junction target at $Path"
}

function Assert-PathMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($null -ne (Get-PathItem -Path $Path)) {
        throw "Unexpected discoverable path: $Path"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingTree,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $safePath = (Resolve-FullPath -Path $WorkingTree).Replace('\', '/')
    $output = @(& git -c "safe.directory=$safePath" @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Git verification failed: $(($output | Out-String).Trim())"
    }
    ($output | Out-String).Trim()
}

function Get-SkillSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)]$SourceConfig,
        [Parameter(Mandatory = $true)]$SelectionConfig,
        [Parameter(Mandatory = $true)][string]$SkillName
    )

    $relativePath = $SkillName
    if ($SelectionConfig.PSObject.Properties.Name -contains 'paths') {
        $pathProperty = $SelectionConfig.paths.PSObject.Properties[$SkillName]
        if ($null -eq $pathProperty) {
            throw "Missing source-path mapping for skill: $SkillName"
        }
        $relativePath = [string]$pathProperty.Value
    }
    Join-Path (Join-Path $SourceRoot ([string]$SourceConfig.skillsDirectory)) $relativePath
}

function Assert-Checkout {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)]$SourceConfig,
        [Parameter(Mandatory = $true)]$SelectionConfig
    )

    Assert-Directory -Path $SourceRoot -Label "$($SourceConfig.name) checkout"
    if ($null -eq (Get-PathItem -Path (Join-Path $SourceRoot '.git'))) {
        throw "Missing preserved Git metadata: $SourceRoot"
    }
    Assert-File -Path (Join-Path $SourceRoot ([string]$SourceConfig.licenseFile)) -Label "$($SourceConfig.name) license"

    $actualCommit = Invoke-Git -WorkingTree $SourceRoot -Arguments @('-C', $SourceRoot, 'rev-parse', 'HEAD')
    Assert-StringEqual -Actual $actualCommit -Expected ([string]$SourceConfig.commit) -Label "$($SourceConfig.name) commit"
    $status = Invoke-Git -WorkingTree $SourceRoot -Arguments @('-C', $SourceRoot, 'status', '--porcelain', '--untracked-files=all')
    if ($status) {
        throw "Installed upstream checkout contains local changes: $SourceRoot"
    }

    foreach ($skillName in @($SelectionConfig.active) + @($SelectionConfig.inactive)) {
        $skillRoot = Get-SkillSourcePath `
            -SourceRoot $SourceRoot `
            -SourceConfig $SourceConfig `
            -SelectionConfig $SelectionConfig `
            -SkillName $skillName
        Assert-File -Path (Join-Path $skillRoot 'SKILL.md') -Label "$($SourceConfig.name) skill $skillName"
    }
}

function Assert-HashRecords {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)]$Records,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $rootFull = Resolve-FullPath -Path $Root
    $expectedPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($record in @($Records)) {
        $relativePath = ([string]$record.path).Replace('/', '\')
        [void]$expectedPaths.Add($relativePath)
        $filePath = Join-Path $rootFull $relativePath
        Assert-File -Path $filePath -Label "$Label file"
        $actualHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne [string]$record.sha256) {
            throw "$Label hash mismatch: $filePath"
        }
    }

    $actualPaths = @(
        Get-ChildItem -LiteralPath $rootFull -File -Recurse |
            ForEach-Object { $_.FullName.Substring($rootFull.Length).TrimStart('\') }
    )
    foreach ($actualPath in $actualPaths) {
        if (-not $expectedPaths.Contains($actualPath)) {
            throw "Unexpected $Label file: $(Join-Path $rootFull $actualPath)"
        }
    }
    if ($actualPaths.Count -ne $expectedPaths.Count) {
        throw "$Label file-count mismatch. Expected $($expectedPaths.Count); found $($actualPaths.Count)"
    }
}

function Assert-ExactChildDirectories {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$ExpectedNames,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $items = @(Get-ChildItem -LiteralPath $Root -Force)
    $actual = @($items | Select-Object -ExpandProperty Name | Sort-Object)
    $expected = @($ExpectedNames | Sort-Object)
    if (($actual -join "`n") -ne ($expected -join "`n")) {
        throw "$Label entry set mismatch. Expected [$($expected -join ', ')]; found [$($actual -join ', ')]"
    }
    foreach ($item in $items) {
        if (-not $item.PSIsContainer) {
            throw "$Label contains a non-directory entry: $($item.FullName)"
        }
    }
}

$installFull = Resolve-FullPath -Path $InstallRoot
$discoveryFull = Resolve-FullPath -Path $DiscoveryRoot
$manifestPath = Join-Path $installFull 'install-manifest.json'
$sourcesLockPath = Join-Path $installFull 'config\sources.lock.json'
$selectionPath = Join-Path $installFull 'config\skill-selection.json'

Assert-Directory -Path $installFull -Label 'GrillPowers installation'
Assert-File -Path $manifestPath -Label 'install manifest'
Assert-File -Path $sourcesLockPath -Label 'installed source lock'
Assert-File -Path $selectionPath -Label 'installed skill selection config'

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$sourcesLock = Get-Content -LiteralPath $sourcesLockPath -Raw | ConvertFrom-Json
$selection = Get-Content -LiteralPath $selectionPath -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or $sourcesLock.schemaVersion -ne 1 -or $selection.schemaVersion -ne 1) {
    throw 'Unsupported GrillPowers schema.'
}
Assert-HashRecords -Root (Join-Path $installFull 'config') -Records $manifest.configurationFiles -Label 'configuration'
Assert-HashRecords -Root (Join-Path $installFull 'scripts') -Records $manifest.managementFiles -Label 'management script'
Assert-StringEqual -Actual (Resolve-FullPath -Path ([string]$manifest.installRoot)) -Expected $installFull -Label 'Manifest InstallRoot'
Assert-StringEqual -Actual (Resolve-FullPath -Path ([string]$manifest.discoveryRoot)) -Expected $discoveryFull -Label 'Manifest DiscoveryRoot'
Assert-StringEqual -Actual ([string]$manifest.sourceCommits.mattpocock) -Expected ([string]$sourcesLock.sources.mattpocock.commit) -Label 'Manifest Matt commit'
Assert-StringEqual -Actual ([string]$manifest.sourceCommits.superpowers) -Expected ([string]$sourcesLock.sources.superpowers.commit) -Label 'Manifest Superpowers commit'

$mattInstall = Join-Path $installFull "sources\$($sourcesLock.sources.mattpocock.checkoutDirectory)"
$superpowersInstall = Join-Path $installFull "sources\$($sourcesLock.sources.superpowers.checkoutDirectory)"
Assert-Checkout -SourceRoot $mattInstall -SourceConfig $sourcesLock.sources.mattpocock -SelectionConfig $selection.mattpocock
Assert-Checkout -SourceRoot $superpowersInstall -SourceConfig $sourcesLock.sources.superpowers -SelectionConfig $selection.superpowers

$originalSkillRoot = Join-Path $installFull 'skills\grill-powers'
Assert-HashRecords -Root $originalSkillRoot -Records $manifest.originalSkillFiles -Label 'original skill'

$mattRouting = Join-Path $installFull 'routing\mattpocock'
$superpowersRouting = Join-Path $installFull 'routing\superpowers'
Assert-Directory -Path $mattRouting -Label 'Matt routing root'
Assert-Directory -Path $superpowersRouting -Label 'Superpowers routing root'

foreach ($skillName in @($selection.mattpocock.active)) {
    $skillTarget = Get-SkillSourcePath `
        -SourceRoot $mattInstall `
        -SourceConfig $sourcesLock.sources.mattpocock `
        -SelectionConfig $selection.mattpocock `
        -SkillName $skillName
    Assert-JunctionTarget -Path (Join-Path $mattRouting $skillName) -ExpectedTarget $skillTarget
}
foreach ($skillName in @($selection.mattpocock.inactive)) {
    Assert-PathMissing -Path (Join-Path $mattRouting $skillName)
}
Assert-ExactChildDirectories -Root $mattRouting -ExpectedNames @($selection.mattpocock.active) -Label 'Matt routing'

foreach ($skillName in @($selection.superpowers.active)) {
    Assert-JunctionTarget -Path (Join-Path $superpowersRouting $skillName) -ExpectedTarget (Join-Path $superpowersInstall "skills\$skillName")
}
$superpowersSupportRoots = @(
    $selection.superpowers.supportPaths |
        ForEach-Object { ($_ -split '/')[0] } |
        Select-Object -Unique
)
foreach ($skillName in @($selection.superpowers.inactive)) {
    if ($superpowersSupportRoots -notcontains $skillName) {
        Assert-PathMissing -Path (Join-Path $superpowersRouting $skillName)
    }
}
foreach ($supportPath in @($selection.superpowers.supportPaths)) {
    Assert-JunctionTarget -Path (Join-Path $superpowersRouting $supportPath) -ExpectedTarget (Join-Path $superpowersInstall "skills\$supportPath")
}
$superpowersTopLevel = @($selection.superpowers.active) + $superpowersSupportRoots
Assert-ExactChildDirectories -Root $superpowersRouting -ExpectedNames $superpowersTopLevel -Label 'Superpowers routing'
foreach ($supportRoot in $superpowersSupportRoots) {
    $supportChildren = @(
        foreach ($configuredSupportPath in @($selection.superpowers.supportPaths)) {
            $segments = ([string]$configuredSupportPath -replace '\\', '/') -split '/'
            if ($segments.Count -gt 1 -and $segments[0] -eq $supportRoot) {
                $segments[1]
            }
        }
    )
    $supportChildren = @($supportChildren | Select-Object -Unique)
    Assert-ExactChildDirectories `
        -Root (Join-Path $superpowersRouting $supportRoot) `
        -ExpectedNames $supportChildren `
        -Label "Superpowers support root $supportRoot"
}
Assert-PathMissing -Path (Join-Path $superpowersRouting 'using-superpowers\SKILL.md')

$originalDiscovery = Join-Path $discoveryFull ([string]$selection.discoveryLinks.original)
$mattDiscovery = Join-Path $discoveryFull ([string]$selection.discoveryLinks.mattpocock)
$superpowersDiscovery = Join-Path $discoveryFull ([string]$selection.discoveryLinks.superpowers)
Assert-JunctionTarget -Path $originalDiscovery -ExpectedTarget $originalSkillRoot
Assert-JunctionTarget -Path $mattDiscovery -ExpectedTarget $mattRouting
Assert-JunctionTarget -Path $superpowersDiscovery -ExpectedTarget $superpowersRouting

[PSCustomObject]@{
    status = 'verified'
    installRoot = $installFull
    discoveryRoot = $discoveryFull
    sourceCommits = [ordered]@{
        mattpocock = [string]$sourcesLock.sources.mattpocock.commit
        superpowers = [string]$sourcesLock.sources.superpowers.commit
    }
    activeSkills = [ordered]@{
        mattpocock = @($selection.mattpocock.active).Count
        superpowers = @($selection.superpowers.active).Count
        original = 1
    }
} | ConvertTo-Json -Depth 5
