# Requires -Version 7
# Version 2.0.0

# check if newer version
#$gistUrl = "https://gist.github.com/rumdood/88a56918088a939f3c08f32ab2bbfe74"
#$latestVersionFile = [System.IO.Path]::Combine("$HOME",'.latest_profile_version')
#$versionRegEx = "# Version (?<version>\d+\.\d+\.\d+)"

#if ([System.IO.File]::Exists($latestVersionFile)) {
#    $latestVersion = [System.IO.File]::ReadAllText($latestVersionFile)
#    $currentProfile = [System.IO.File]::ReadAllText($profile)
#    [version]$currentVersion = "0.0.0"
#
#    if ($currentProfile -match $versionRegEx) {
#        $currentVersion = $matches.Version
#    }
#
#    if ([version]$latestVersion -gt $currentVersion) {
#        Write-Verbose "Your version: $currentVersion" -Verbose
#        Write-Verbose "New version: $latestVersion" -Verbose
#        $choice = Read-Host -Prompt "Found newer profile, install? (Y)"
#        if ($choice -eq "Y" -or $choice -eq "") {
#            try {
#                $gist = Invoke-RestMethod $gistUrl -ErrorAction Stop
#                $gistProfile = $gist.Files."profile.ps1".Content
#                Set-Content -Path $profile -Value $gistProfile
#                Write-Verbose "Installed newer version of profile" -Verbose
#                . $profile
#                return
#            }
#            catch {
#               # we can hit rate limit issue with GitHub since we're using anonymous
#               Write-Verbose -Verbose "Was not able to access gist, try again next time"
#           }
#       }
#   }
#}

$global:profile_initialized = $false

# set PowerShell to UTF-8
[console]::InputEncoding = [console]::OutputEncoding = New-Object System.Text.UTF8Encoding

$poshThemePath = [System.Environment]::GetEnvironmentVariable("POSH_THEMES_PATH")

if ($null -eq $poshThemePath -or '' -eq $poshThemePath) {
    Write-Warning "!!! OhMyPosh does not appear to be installed as a winget package !!!"
} else {
    [System.Environment]::SetEnvironmentVariable("POSH_GIT_ENABLED", $true)
    Import-Module -Name posh-git
    Import-Module -Name Terminal-Icons
    oh-my-posh init pwsh --config "$poshThemePath\rumdood.omp.json" | Invoke-Expression
    $ohMyPoshInstalledFlag = $true
}

# HISTORY
Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle ListView
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

# I'm lazy, dont' make me type 64
Set-Alias -Name rider -Value rider64
# I can never remember which of these I used cause I'm not smart
Set-Alias -Name gitPublish -Value Publish-Branch
Set-Alias -Name gitPub -Value Publish-Branch

# General Functions

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

function Publish-Branch {
    $branch = git rev-parse --abbrev-ref HEAD
    git push --set-upstream origin $branch

    Open-GitRemote
}

function Get-Latest {
    $branch = git rev-parse --abbrev-ref HEAD

    Write-Host "Pulling from origin/$branch`n"
    git pull origin $branch
}

function Get-GitHistory {
    Param(
        [Parameter(Position=0, Mandatory=$true)]
        [string] $path,
        [Parameter(Position=1)]
        [Alias('a')]
        [switch] $add,
        [Alias('m')]
        [switch] $modify,
        [Alias('d')]
        [switch] $delete,
        [Alias('c')]
        [switch] $copy,
        [Alias('r')]
        [switch] $rename,
        [Alias('ch')]
        [switch] $changed,
        [Alias('unm')]
        [switch] $unmerged,
        [Alias('unk')]
        [switch] $unknown,
        [Alias('b')]
        [switch] $broken
    )

    $filter = ""

    if ($add) {
        $filter += "A"
    }

    if ($modify) {
        $filter += "M"
    }

    if ($delete) {
        $filter += "D"
    }

    if ($copy) {
        $filter += "C"
    }

    if ($rename) {
        $filter += "R"
    }

    if ($changed) {
        $filter += "T"
    }

    if ($unmerged) {
        $filter += "U"
    }

    if ($unknown) {
        $filter += "X"
    }

    if ($broken) {
        $filter += "B"
    }
    
    git log --diff-filter=$filter -- $path
}

function Get-GitCurrent {
    $branch = git rev-parse --abbrev-ref HEAD
    git pull origin $branch
}

function Import-GitPatch {
    Param (
        [Parameter(Mandatory=$true)]
        [string] $patchFile
    )

    git apply --3way $patchFile
}

function Export-GitStash {
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

function Restore-GitDeleted {
    git status --porcelain | 
        Where-Object { $_.StartsWith(" D") } | 
        ForEach-Object { git restore $_.Substring(3) }
}

function Import-SingleBranch {
    Param(
        [Parameter(Position=0)]
        [string] $repository,
        [Parameter(Position=1)]
        [string] $branch,
        [Parameter(Position=2)]
        [string] $targetFolder
    )

    if ($null -eq $targetFolder -or "" -eq $targetFolder) {
        $targetFolder = $PWD.Path
    }

    $pathSafeBranchName = $branch.Replace("/", "__")

    Write-Host "############################################################################" -ForegroundColor DarkGreen
    Write-Host "Cloning $repository/$branch into $targetFolder/$pathSafeBranchName..." -ForegroundColor Green
    Write-Host "############################################################################" -ForegroundColor DarkGreen
    git clone -b $branch --single-branch $repository "$targetFolder/$pathSafeBranchName"

    Write-Host "DONE" -ForegroundColor Green

    Set-Location $project/$correctedRelease
}

function Get-RemoteBranch {
    Param(
        [Parameter(Position=0,Mandatory=$true)]
        [string] $remoteBranch,
        [Parameter(Position=1,Mandatory=$false)]
        [switch] $checkout
    )

    git remote set-branches --add origin $remoteBranch
    git fetch origin $($remoteBranch):$($remoteBranch)

    if (!$checkout) {
        return
    }

    git switch $remoteBranch
}

function Set-PoshTheme ([string] $themeName) {
    if (!$ohMyPoshInstalledFlag) {
        Write-Error "OhMyPosh is not installed on this machine. Please install it using WinGet"
        return
    }

    oh-my-posh init pwsh --config "$env:POSH_THEMES_PATH\$themeName.omp.json" | Invoke-Expression
}

function Publish-PoshTheme ([string] $themePath) {
    if (!$ohMyPoshInstalledFlag) {
        Write-Error "OhMyPosh is not installed on this machine. Please install it using WinGet"
        return
    }
    
    Copy-Item -Path $themePath $env:POSH_THEMES_PATH
}

# Taken/adapted from https://dbremen.github.io/2021/04/01/NewSplitPane.html
function New-SplitPane{ 
    [CmdletBinding()]
    [CmdletBinding(DefaultParameterSetName='Process')]
    Param(
        [Parameter(Position=0,ParameterSetName='Process')]
        [ScriptBlock]$Begin,
        [Parameter(Mandatory,Position=1,ParameterSetName='Process')]
        [ScriptBlock]$Process,
        [Parameter(ParameterSetName='Process')]
        [TimeSpan]$Interval,
        [Parameter(ParameterSetName='Static')]
        $ScriptBlock,
        [ValidateRange(0.0,1.0)]
        [float]$Size,
        $ProfileName = 'NoProfile',
        [ValidateSet('Vertical','Horizontal')]
        $Orientation = 'Vertical'
    )
    #keep track of the powershell process id's prior to invoking the new panel process
    $before = Get-Process pwsh
    $command = ' -w 0 sp'
    if ($Size) { $command += " -s $Size" }
    if ($ProfileName){ $command += " -p ""$ProfileName""" }
    if ($Orientation){ $command += " --$($Orientation.ToLower())" }

    if ($PSCmdlet.ParameterSetName -eq 'Process'){
        $scriptText = "{`n"
        if ($Begin){ 
            $scriptText += "$($Begin.ToString()) `n"
        } 

        if ($Interval -gt 0) {
            #wrap the process block into an endless loop and the specified sleep interval
            $scriptText += 'while($true){' + "`n"
        }

        $scriptText += "$($Process.ToString()) `n"

        if ($Interval -gt 0) {
            $scriptText += 'sleep -Seconds ' + $Interval.TotalSeconds + '}' + "`n"
        }

        $scriptText += '}'
    }
    else{
        $scriptText = $ScriptBlock
    }

    $backDirection = $Orientation -eq 'Vertical' ? 'Left' : 'Up'

    $scriptText += '; move-focus ' + $backDirection

    #$encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptText))
    #$command += ' "Powershell" pwsh -nop -noexit -encodedCommand ' + $encodedCommand
    $command += ' "Powershell" pwsh -nop -noexit -command ' + $scriptText

    Start-Process  wt.exe $command -Wait

    #retrieve the new process id and return it
    $proc = $null

    do {
        Start-Sleep -Seconds 1
        $proc = (Get-Process pwsh).Where{$_.id -notin $before.Id}
    } while ($null -eq $proc -or "" -eq $proc)

    return $proc
}

function Get-MarloweTask {
    Param(
        [Parameter(ParameterSetName="all")]
        [switch] $all = $false,
        [Parameter(ParameterSetName="single")]
        [string] $name,
        [Parameter(ParameterSetName="single")]
        [long] $chatId=$ENV:MarloweChatId
    )
    $headers = @{
        "x-functions-key" = "$($ENV:MarloweFunctionKey)"
    }

    $url = $all ? "$ENV:MarloweBaseUrl/tasks" : "$ENV:MarloweBaseUrl/$chatId/tasks/$name"

    Invoke-RestMethod -Uri $url -Headers $headers
}

function Set-MarloweTask {
    Param(
        [Parameter(Mandatory=$true)]
        [string] $name,
        [long] $chatId=$ENV:MarloweChatId,
        [Parameter(ParameterSetName="complete")]
        [switch] $complete,
        [Parameter(ParameterSetName="skip")]
        [switch] $skip
    )

    if (!$complete -and !$skip) {
        Write-Error "You must either complete or skip the task"
        return
    }

    $headers = @{
        "x-functions-key" = "$($ENV:MarloweFunctionKey)"
    }

    $action = $complete ? "complete" : "skip"

    Invoke-RestMethod -Uri "$ENV:MarloweBaseUrl/$chatId/tasks/$name/$action" -Headers $headers -Method Post
}

function Get-WingetList {
    Param(
        [Parameter(ParameterSetName = "installed")]
        [switch] $installed,
        [string] $filter
    )

    $verb = $installed ? "list" : "search"

    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
    (Invoke-Expression "winget $verb $filter") -match '^(\p{L}|-)' |
        ConvertFrom-FixedColumnTable
}

# Borrowed from https://stackoverflow.com/a/74297741/311340 with some minor
#   minor modifications to fix column name processing when there's an overflow
#
# Note:
#  * Accepts input only via the pipeline, either line by line, 
#    or as a single, multi-line string.
#  * The input is assumed to have a header line whose column names
#    mark the start of each field
#    * Column names are assumed to be *single words* (must not contain spaces).
#  * The header line is assumed to be followed by a separator line
#    (its format doesn't matter).
function ConvertFrom-FixedColumnTable {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)] 
        [string] $InputObject
    )

    begin {
        $lineNdx = 0
    }

    process {
        $lines = 
        if ($InputObject.Contains("`n")) { $InputObject.TrimEnd("`r", "`n") -split '\r?\n' }
        else { $InputObject }
        foreach ($line in $lines) {
        ++$lineNdx
        if ($lineNdx -eq 1) { 
            # header line
            $headerLine = $line 
        }
        elseif ($lineNdx -eq 2) { 
            # separator line
            $maxLineLen = $line.Length
            # Get the indices where the fields start.
            $fieldStartIndices = [regex]::Matches($headerLine, '\b\S').Index
            # Calculate the field lengths.
            $fieldLengths = foreach ($i in 1..$fieldStartIndices.Count) { 
            ($fieldStartIndices[$i], ($maxLineLen + 1))[$i -eq $fieldStartIndices.Count] - $fieldStartIndices[$i - 1] - 1
            }
            # Get the column names
            $colNames = foreach ($i in 0..($fieldStartIndices.Count - 1)) {
            ($fieldStartIndices[$i] + $fieldLengths[$i] -gt $headerLine.Length) ? $headerLine.Substring($fieldStartIndices[$i]) : $headerLine.Substring($fieldStartIndices[$i], $fieldLengths[$i]).Trim()
            } 
        }
        else {
            # data line
            $oht = [ordered] @{} # ordered helper hashtable for object constructions.
            $i = 0
            foreach ($colName in $colNames) {
            $oht[$colName] = 
            if ($fieldStartIndices[$i] -lt $line.Length) {
                if ($fieldStartIndices[$i] + $fieldLengths[$i] -le $line.Length) {
                $line.Substring($fieldStartIndices[$i], $fieldLengths[$i]).Trim()
                }
                else {
                $line.Substring($fieldStartIndices[$i]).Trim()
                }
            }
            ++$i
            }
            # Convert the helper hashable to an object and output it.
            [pscustomobject] $oht
        }
        }
    }
}

function Update-Path {
    Param(
        [Parameter(ParameterSetName = "append")]
        [switch] $append,
        [Parameter(ParameterSetName = "set")]
        [switch] $set,
        [Parameter(ParameterSetName = "user")]
        [switch] $user,
        [Parameter(ParameterSetName = "machine")]
        [switch] $machine,
        [Parameter(Mandatory=$true)]
        [string] $value
    )

    $separator = [System.IO.Path]::PathSeparator
    $scope = $machine ? "MACHINE" : "USER"

    if ($append) {
        Write-Host "Adding to $scope"
        $Path = [System.Environment]::GetEnvironmentVariable("PATH", $scope);

        if (!$Path.EndsWith($separator)) {
            $Path += $separator
        }

        $Path += $value

        [System.Environment]::SetEnvironmentVariable("PATH", $Path, $scope)
    }
}

function Get-YesNoResponse {
    Param(
        [string] $question
    )

    do {
        try {
            [ValidateSet('Y','N', '')]$answer = $(Write-Host $question -ForegroundColor Yellow -NoNewline; Read-Host)
        } catch {
            Write-Error "Invalid Entry - it's a Yes or No question"
        }
    } until ($answer -in 'Y', 'N', '')

    return $answer -eq 'Y'
}

if (!$ohMyPoshInstalledFlag) {
    $installFlag = Get-YesNoResponse "WARNING: OhMyPosh is not installed on this system. Do you wish to install it? (Y/N) "

    if ($installFlag) {
        winget install JanDeDobbeleer.OhMyPosh
    }
}

if ($global:profile_initialized -ne $true) {
    $global:profile_initialized = $true
}

# Computer-Specific Code Goes below this line
#####################################################################################################
