[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MattSourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$SuperpowersSourceRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptRoot
$installScript = Join-Path $scriptRoot 'install.ps1'
$verifyScript = Join-Path $scriptRoot 'verify.ps1'
$sourcesLock = Join-Path $repositoryRoot 'config\sources.lock.json'
$selectionConfig = Join-Path $repositoryRoot 'config\skill-selection.json'
$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$testRoot = Join-Path $tempBase ('.grill-powers-test-' + [guid]::NewGuid().ToString('N'))
$passed = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-PathMissing {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    Assert-True -Condition ($null -eq $item) -Message "Expected path to remain absent: $Path"
}

function Assert-JunctionTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedTarget
    )

    $item = Get-Item -LiteralPath $Path -Force
    Assert-True `
        -Condition ([bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)) `
        -Message "Expected a directory junction: $Path"

    $actualTargets = @($item.Target)
    Assert-True -Condition ($actualTargets.Count -eq 1) -Message "Expected one junction target at: $Path"

    $actual = [System.IO.Path]::GetFullPath([string]$actualTargets[0]).TrimEnd('\')
    $expected = [System.IO.Path]::GetFullPath($ExpectedTarget).TrimEnd('\')
    Assert-True `
        -Condition ($actual.Equals($expected, [System.StringComparison]::OrdinalIgnoreCase)) `
        -Message "Unexpected junction target at $Path. Expected $expected; found $actual"
}

function Invoke-PowerShellFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $powershell = (Get-Process -Id $PID).Path
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $Path @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    [PSCustomObject]@{
        ExitCode = $exitCode
        Output = $output
        Text = ($output | Out-String).Trim()
    }
}

function Remove-JunctionIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)

    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return
    }
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) {
        [System.IO.Directory]::Delete($item.FullName, $false)
    }
}

function Remove-TestRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if (-not $fullPath.StartsWith($tempBase, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a path outside the test temp root: $fullPath"
    }

    foreach ($discoveryName in @('grill-powers', 'mattpocock', 'superpowers')) {
        Remove-JunctionIfPresent -Path (Join-Path $fullPath "discovery\$discoveryName")
        Remove-JunctionIfPresent -Path (Join-Path $fullPath "conflict-discovery\$discoveryName")
    }

    $routingRoot = Join-Path $fullPath 'install\routing'
    foreach ($routingFamily in @('mattpocock', 'superpowers')) {
        $familyPath = Join-Path $routingRoot $routingFamily
        if (Test-Path -LiteralPath $familyPath -PathType Container) {
            Get-ChildItem -LiteralPath $familyPath -Force -Recurse -Attributes ReparsePoint -ErrorAction SilentlyContinue |
                Sort-Object -Property FullName -Descending |
                ForEach-Object { [System.IO.Directory]::Delete($_.FullName, $false) }
        }
    }

    if (Test-Path -LiteralPath $fullPath) {
        Remove-Item -LiteralPath $fullPath -Recurse -Force
    }
}

try {
    Assert-True -Condition (Test-Path -LiteralPath $installScript -PathType Leaf) -Message "Missing installer: $installScript"
    Assert-True -Condition (Test-Path -LiteralPath $verifyScript -PathType Leaf) -Message "Missing verifier: $verifyScript"
    Assert-True -Condition (Test-Path -LiteralPath $sourcesLock -PathType Leaf) -Message "Missing source lock: $sourcesLock"
    Assert-True -Condition (Test-Path -LiteralPath $selectionConfig -PathType Leaf) -Message "Missing skill selection: $selectionConfig"

    foreach ($scriptPath in @($installScript, $verifyScript)) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        Assert-True -Condition ($errors.Count -eq 0) -Message "PowerShell parser errors in $scriptPath`: $($errors -join '; ')"
    }
    $passed.Add('PowerShell syntax parses')

    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $installRoot = Join-Path $testRoot 'install'
    $discoveryRoot = Join-Path $testRoot 'discovery'

    $installSource = Get-Content -LiteralPath $installScript -Raw
    Assert-True `
        -Condition ($installSource -match '\[System\.IO\.Directory\]::Move\(\$stagingRoot, \$installFull\)') `
        -Message 'Installer does not use an atomic destination claim for InstallRoot.'
    Assert-True `
        -Condition ($installSource -notmatch 'Move-Item\s+-LiteralPath\s+\$stagingRoot\s+-Destination\s+\$installFull') `
        -Message 'Installer still uses nesting Move-Item semantics for InstallRoot.'
    Assert-True `
        -Condition ($installSource -notmatch 'SupportsShouldProcess') `
        -Message 'Installer advertises ShouldProcess without honoring confirmation.'
    Assert-True `
        -Condition ($installSource -match '\[switch\]\$WhatIf') `
        -Message 'Installer is missing its explicit WhatIf switch.'
    $atomicSource = Join-Path $testRoot 'atomic-source'
    $atomicDestination = Join-Path $testRoot 'atomic-destination'
    New-Item -ItemType Directory -Path $atomicSource, $atomicDestination | Out-Null
    Set-Content -LiteralPath (Join-Path $atomicDestination 'sentinel.txt') -Value 'owned elsewhere'
    $atomicMoveRejected = $false
    try {
        [System.IO.Directory]::Move($atomicSource, $atomicDestination)
    }
    catch {
        $atomicMoveRejected = $true
    }
    Assert-True -Condition $atomicMoveRejected -Message 'Directory.Move accepted an existing destination.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $atomicDestination 'sentinel.txt') -PathType Leaf) -Message 'Atomic destination test damaged the raced-in directory.'
    $passed.Add('Atomic InstallRoot claim rejects a raced-in destination')

    $commonArguments = @(
        '-InstallRoot', $installRoot,
        '-DiscoveryRoot', $discoveryRoot,
        '-MattSourceRoot', ([System.IO.Path]::GetFullPath($MattSourceRoot)),
        '-SuperpowersSourceRoot', ([System.IO.Path]::GetFullPath($SuperpowersSourceRoot))
    )

    $nestedDiscoveryRoot = Join-Path ([System.IO.Path]::GetFullPath($MattSourceRoot)) '.grill-powers-discovery-test'
    $nestedDiscoveryArguments = @(
        '-InstallRoot', (Join-Path $testRoot 'nested-source-install'),
        '-DiscoveryRoot', $nestedDiscoveryRoot,
        '-MattSourceRoot', ([System.IO.Path]::GetFullPath($MattSourceRoot)),
        '-SuperpowersSourceRoot', ([System.IO.Path]::GetFullPath($SuperpowersSourceRoot)),
        '-WhatIf'
    )
    $nestedDiscovery = Invoke-PowerShellFile -Path $installScript -Arguments $nestedDiscoveryArguments
    Assert-True -Condition ($nestedDiscovery.ExitCode -ne 0) -Message 'Installer accepted DiscoveryRoot inside a local source checkout.'
    Assert-True -Condition ($nestedDiscovery.Text -match 'DiscoveryRoot cannot be inside local source checkout') -Message "Unexpected nested-discovery error: $($nestedDiscovery.Text)"
    Assert-PathMissing -Path $nestedDiscoveryRoot
    $passed.Add('DiscoveryRoot cannot modify a local source checkout')

    $packagedSkillDiscoveryRoot = Join-Path $repositoryRoot 'skills\grill-powers\.discovery-test'
    $packagedSkillDiscoveryArguments = @(
        '-InstallRoot', (Join-Path $testRoot 'packaged-skill-install'),
        '-DiscoveryRoot', $packagedSkillDiscoveryRoot,
        '-MattSourceRoot', ([System.IO.Path]::GetFullPath($MattSourceRoot)),
        '-SuperpowersSourceRoot', ([System.IO.Path]::GetFullPath($SuperpowersSourceRoot)),
        '-WhatIf'
    )
    $packagedSkillDiscovery = Invoke-PowerShellFile -Path $installScript -Arguments $packagedSkillDiscoveryArguments
    Assert-True -Condition ($packagedSkillDiscovery.ExitCode -ne 0) -Message 'Installer accepted DiscoveryRoot inside the packaged skill.'
    Assert-True -Condition ($packagedSkillDiscovery.Text -match 'DiscoveryRoot cannot be inside the packaged GrillPowers skill') -Message "Unexpected packaged-skill DiscoveryRoot error: $($packagedSkillDiscovery.Text)"
    Assert-PathMissing -Path $packagedSkillDiscoveryRoot
    $passed.Add('DiscoveryRoot cannot modify the packaged skill')

    $packagedSkillAlias = Join-Path $testRoot 'packaged-skill-alias'
    $aliasDiscoveryRoot = Join-Path $packagedSkillAlias '.discovery-test'
    try {
        New-Item `
            -ItemType Junction `
            -Path $packagedSkillAlias `
            -Target (Join-Path $repositoryRoot 'skills\grill-powers') | Out-Null
        $aliasDiscoveryArguments = @(
            '-InstallRoot', (Join-Path $testRoot 'alias-install'),
            '-DiscoveryRoot', $aliasDiscoveryRoot,
            '-MattSourceRoot', ([System.IO.Path]::GetFullPath($MattSourceRoot)),
            '-SuperpowersSourceRoot', ([System.IO.Path]::GetFullPath($SuperpowersSourceRoot)),
            '-WhatIf'
        )
        $aliasDiscovery = Invoke-PowerShellFile -Path $installScript -Arguments $aliasDiscoveryArguments
    }
    finally {
        Remove-JunctionIfPresent -Path $packagedSkillAlias
    }
    Assert-True -Condition ($aliasDiscovery.ExitCode -ne 0) -Message 'Installer accepted DiscoveryRoot through a reparse-point alias.'
    Assert-True -Condition ($aliasDiscovery.Text -match 'DiscoveryRoot cannot traverse a reparse point') -Message "Unexpected reparse-point error: $($aliasDiscovery.Text)"
    Assert-PathMissing -Path (Join-Path $repositoryRoot 'skills\grill-powers\.discovery-test')
    $passed.Add('Reparse-point aliases cannot bypass containment guards')

    $dryRun = Invoke-PowerShellFile -Path $installScript -Arguments ($commonArguments + '-WhatIf')
    Assert-True -Condition ($dryRun.ExitCode -eq 0) -Message "Dry run failed: $($dryRun.Text)"
    Assert-PathMissing -Path $installRoot
    Assert-PathMissing -Path $discoveryRoot
    $dryRunResult = $dryRun.Text | ConvertFrom-Json
    Assert-True -Condition ($dryRunResult.mode -eq 'WhatIf') -Message 'Dry run did not report WhatIf mode.'
    $passed.Add('WhatIf reports the plan without writes')

    $conflictInstallRoot = Join-Path $testRoot 'conflict-install'
    $conflictDiscoveryRoot = Join-Path $testRoot 'conflict-discovery'
    New-Item -ItemType Directory -Path (Join-Path $conflictDiscoveryRoot 'mattpocock') -Force | Out-Null
    $conflictArguments = @(
        '-InstallRoot', $conflictInstallRoot,
        '-DiscoveryRoot', $conflictDiscoveryRoot,
        '-MattSourceRoot', ([System.IO.Path]::GetFullPath($MattSourceRoot)),
        '-SuperpowersSourceRoot', ([System.IO.Path]::GetFullPath($SuperpowersSourceRoot))
    )
    $conflict = Invoke-PowerShellFile -Path $installScript -Arguments $conflictArguments
    Assert-True -Condition ($conflict.ExitCode -ne 0) -Message 'Installer accepted an existing discovery path.'
    Assert-True -Condition ($conflict.Text -match 'Refusing to overwrite') -Message "Unexpected conflict error: $($conflict.Text)"
    Assert-PathMissing -Path $conflictInstallRoot
    $passed.Add('Preflight rejects existing targets before writes')

    $install = Invoke-PowerShellFile -Path $installScript -Arguments $commonArguments
    Assert-True -Condition ($install.ExitCode -eq 0) -Message "Install failed: $($install.Text)"
    $installResult = $install.Text | ConvertFrom-Json
    Assert-True -Condition ($installResult.status -eq 'installed') -Message 'Installer did not report installed status.'

    $verifyArguments = @('-InstallRoot', $installRoot, '-DiscoveryRoot', $discoveryRoot)
    $verify = Invoke-PowerShellFile -Path $verifyScript -Arguments $verifyArguments
    Assert-True -Condition ($verify.ExitCode -eq 0) -Message "Verification failed: $($verify.Text)"
    $verifyResult = $verify.Text | ConvertFrom-Json
    Assert-True -Condition ($verifyResult.status -eq 'verified') -Message 'Verifier did not report verified status.'
    $passed.Add('Isolated installation verifies')

    $lock = Get-Content -LiteralPath $sourcesLock -Raw | ConvertFrom-Json
    $selection = Get-Content -LiteralPath $selectionConfig -Raw | ConvertFrom-Json
    $mattInstall = Join-Path $installRoot "sources\$($lock.sources.mattpocock.checkoutDirectory)"
    $superpowersInstall = Join-Path $installRoot "sources\$($lock.sources.superpowers.checkoutDirectory)"

    foreach ($sourceInstall in @($mattInstall, $superpowersInstall)) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $sourceInstall '.git') -PathType Container) -Message "Missing preserved Git metadata: $sourceInstall"
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $sourceInstall 'LICENSE') -PathType Leaf) -Message "Missing preserved upstream license: $sourceInstall"
    }
    $installedOriginalSkill = Join-Path $installRoot 'skills\grill-powers'
    foreach ($legalPath in @(
        'LICENSE',
        'THIRD_PARTY_NOTICES.md',
        'LICENSES\mattpocock-skills-MIT.txt',
        'LICENSES\superpowers-MIT.txt'
    )) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installedOriginalSkill $legalPath) -PathType Leaf) -Message "Missing installed GrillPowers legal file: $legalPath"
    }
    $passed.Add('Installed GrillPowers skill carries license and third-party notices')
    foreach ($inactiveSkill in $selection.mattpocock.inactive) {
        $relativeSkillPath = [string]$selection.mattpocock.paths.PSObject.Properties[[string]$inactiveSkill].Value
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $mattInstall "skills\$relativeSkillPath\SKILL.md") -PathType Leaf) -Message "Missing inactive Matt source skill: $inactiveSkill"
        Assert-PathMissing -Path (Join-Path $installRoot "routing\mattpocock\$inactiveSkill")
    }
    foreach ($inactiveSkill in $selection.superpowers.inactive) {
        Assert-True -Condition (Test-Path -LiteralPath (Join-Path $superpowersInstall "skills\$inactiveSkill\SKILL.md") -PathType Leaf) -Message "Missing inactive Superpowers source skill: $inactiveSkill"
    }
    Assert-PathMissing -Path (Join-Path $installRoot 'routing\superpowers\brainstorming')
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $installRoot 'routing\superpowers\using-superpowers\SKILL.md') -PathType Leaf)) -Message 'using-superpowers unexpectedly became discoverable.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installRoot 'routing\superpowers\using-superpowers\references') -PathType Container) -Message 'Missing Superpowers support references.'
    $passed.Add('Full upstream trees and licenses are preserved while discovery is curated')

    Assert-JunctionTarget -Path (Join-Path $discoveryRoot 'grill-powers') -ExpectedTarget (Join-Path $installRoot 'skills\grill-powers')
    Assert-JunctionTarget -Path (Join-Path $discoveryRoot 'mattpocock') -ExpectedTarget (Join-Path $installRoot 'routing\mattpocock')
    Assert-JunctionTarget -Path (Join-Path $discoveryRoot 'superpowers') -ExpectedTarget (Join-Path $installRoot 'routing\superpowers')
    $passed.Add('Discovery junctions target the installed curated roots')

    $unexpectedMattFile = Join-Path $installRoot 'routing\mattpocock\SKILL.md'
    Set-Content -LiteralPath $unexpectedMattFile -Value 'unexpected discoverable skill'
    $unexpectedMattCheck = Invoke-PowerShellFile -Path $verifyScript -Arguments $verifyArguments
    Remove-Item -LiteralPath $unexpectedMattFile -Force
    Assert-True -Condition ($unexpectedMattCheck.ExitCode -ne 0) -Message 'Verifier accepted an unexpected namespace-level Matt skill file.'
    Assert-True -Condition ($unexpectedMattCheck.Text -match 'entry set mismatch') -Message "Unexpected routing-file error: $($unexpectedMattCheck.Text)"

    $unexpectedSupportFile = Join-Path $installRoot 'routing\superpowers\using-superpowers\unexpected.md'
    Set-Content -LiteralPath $unexpectedSupportFile -Value 'unexpected support entry'
    $unexpectedSupportCheck = Invoke-PowerShellFile -Path $verifyScript -Arguments $verifyArguments
    Remove-Item -LiteralPath $unexpectedSupportFile -Force
    Assert-True -Condition ($unexpectedSupportCheck.ExitCode -ne 0) -Message 'Verifier accepted an unexpected support-root file.'
    Assert-True -Condition ($unexpectedSupportCheck.Text -match 'entry set mismatch') -Message "Unexpected support-file error: $($unexpectedSupportCheck.Text)"
    $passed.Add('Verifier rejects unexpected discoverable and support entries')

    $manifestPath = Join-Path $installRoot 'install-manifest.json'
    $manifestHashBefore = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    $repeat = Invoke-PowerShellFile -Path $installScript -Arguments $commonArguments
    Assert-True -Condition ($repeat.ExitCode -ne 0) -Message 'Repeated install silently overwrote an existing installation.'
    Assert-True -Condition ($repeat.Text -match 'Refusing to overwrite') -Message "Unexpected repeated-install error: $($repeat.Text)"
    $manifestHashAfter = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash
    Assert-True -Condition ($manifestHashBefore -eq $manifestHashAfter) -Message 'Repeated install changed the existing manifest.'
    $passed.Add('Repeated install refuses overwrite and preserves existing data')

    $installedLock = Join-Path $installRoot 'config\sources.lock.json'
    Add-Content -LiteralPath $installedLock -Value "`n "
    $configTamperCheck = Invoke-PowerShellFile -Path $verifyScript -Arguments $verifyArguments
    Assert-True -Condition ($configTamperCheck.ExitCode -ne 0) -Message 'Verifier accepted a modified installed lock file.'
    Assert-True -Condition ($configTamperCheck.Text -match 'configuration hash') -Message "Unexpected config-tamper error: $($configTamperCheck.Text)"
    Copy-Item -LiteralPath $sourcesLock -Destination $installedLock -Force
    $passed.Add('Verifier detects installed configuration tampering')

    Add-Content -LiteralPath (Join-Path $installRoot 'skills\grill-powers\SKILL.md') -Value "`n# tamper-test"
    $tamperCheck = Invoke-PowerShellFile -Path $verifyScript -Arguments $verifyArguments
    Assert-True -Condition ($tamperCheck.ExitCode -ne 0) -Message 'Verifier accepted a modified original skill.'
    Assert-True -Condition ($tamperCheck.Text -match 'hash') -Message "Unexpected tamper error: $($tamperCheck.Text)"
    $passed.Add('Verifier detects installed skill tampering')

    [PSCustomObject]@{
        status = 'passed'
        assertions = $passed.Count
        checks = @($passed)
    } | ConvertTo-Json -Depth 4
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-TestRoot -Path $testRoot
    }
}
