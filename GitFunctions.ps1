Import-Module -Name "./CommonFunctions.ps1" -force

function Publish-Branch {
    $branch = git rev-parse --abbrev-ref HEAD
    git push --set-upstream origin $branch
}

function Open-GitRemote {
    $remoteUrl = git config remote.origin.url

    # ssh, gonna have to do more parsing
    $urlPieces = $remoteUrl | Select-String -Pattern '(:git|ssh|https?|git@[-\w.]+):(\/\/)?(.*?)(\.git)?(\/?|\#[-\d\w._]+?)$' -AllMatches

    if ($urlPieces.Matches.Count -eq 0) {
        Write-Host "Unrecognized ORIGIN format: $remoteUrl" -ForegroundColor Red
        return
    }

    $protocol = $urlPieces.Matches.Groups[1].Value

    switch ($protocol) {
        "https" {
            Start-Process $remoteUrl
        }
        "git@github.com" {
            Start-Process "https://github.com/$($urlPieces.Matches.Groups[3])"
        }
        default {
            Write-Host "Can't Open That Yet [$remoteUrl]" -ForegroundColor DarkYellow
        }
    }
}

function Import-Patch {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $patchFile
    )

    git apply --3way $patchFile
}

function Export-Stash {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $stashName,
        [Parameter(Mandatory=$true)]
        [string] $exportFile
    )

    $branchName = git rev-parse --abbrev-ref HEAD
    $stashList = git stash list
    $pattern = "stash\@{([\d])}: On $([regex]::escape($branchName.split("/")[-1])): $([regex]::escape($stashName))"

    $m = $stashList | Where-Object { $_ -match $pattern } | Select-String -Pattern $pattern
    $stashIndex = $m.Matches.Groups[1].Value

    Write-Host "Exporing stash [$stashName] at index [$stashIndex] to [$exportFile.patch]"

    git stash show $stashIndex --no-color -p > "$exportFile.patch"
}

function Export-Commits {
    Param(
        [Parameter(Mandatory=$true,Position=0)]
        [int] $numberOfCommits,
        [Parameter(Mandatory=$true,Position=1)]
        [string] $exportFolder,
        [Parameter(Position=2)]
        [switch] $revert
    )

    Write-Host "Exporting $numberOfCommits commits to $exportFolder"
    git format-patch -$numberOfCommits HEAD -o $exportFolder

    if ($revert) {
        Write-Host "Reverting the last $numberofCommits commits"
        $continue = Get-YesNoResponse "This step cannot be undone, are you sure you want to continue?"

        if (!$continue) {
            Write-Host "Cancelling revert, your patch has still been created at $exportFolder" -ForegroundColor Red
            return
        }

        git reset --hard HEAD~$numberOfCommits
    }
}