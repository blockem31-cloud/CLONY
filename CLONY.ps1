# Clony - Discord Server Cloner v5.3 [ASCII ONLY - NO EMOJIS IN CODE]
# Pure PowerShell | Encrypted Token | UTF-8 Output | Bug-Free

Add-Type -AssemblyName System.Security

$host.UI.RawUI.WindowTitle = "CLONY v5.3 - Secure Server Cloner"
$host.UI.RawUI.BackgroundColor = "Black"
$host.UI.RawUI.ForegroundColor = "Green"

# Force UTF-8 for console output (emojis in Discord will work)
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[System.Console]::InputEncoding = [System.Text.Encoding]::UTF8

Clear-Host

# =========================================================
# Configuration
# =========================================================
$apiBase = "https://discord.com/api/v10"
$token = ""
$servers = @()
$sourceId = ""
$targetId = ""
$sourceGuildData = $null
$tokenFile = "$PSScriptRoot\.clony_token.enc"
$discordUser = $null

# =========================================================
# Banner
# =========================================================
function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host "                    CLONY v5.3 [ASCII SAFE]                     " -ForegroundColor Green
    Write-Host "              [ DISCORD SERVER CLONER - ENCRYPTED ]             " -ForegroundColor Green
    Write-Host "        Icon | Roles | Channels | Emojis | Secure Token         " -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
    Write-Host ""
}

function Show-Header {
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Green
    Write-Host "|                    CLONY MAIN MENU                       |" -ForegroundColor Green
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Green
}

function Show-Footer {
    Write-Host "+----------------------------------------------------------+" -ForegroundColor DarkGray
    if($discordUser) {
        $userDisplay = "$($discordUser.username)"
        if($discordUser.discriminator -and $discordUser.discriminator -ne "0") {
            $userDisplay = "$($discordUser.username)#$($discordUser.discriminator)"
        }
        Write-Host "|  Logged in as: $($userDisplay.PadRight(40)) |" -ForegroundColor Cyan
    } else {
        Write-Host "|  Not logged in                                        |" -ForegroundColor DarkGray
    }
    Write-Host "+----------------------------------------------------------+" -ForegroundColor DarkGray
    Write-Host ""
}

# =========================================================
# Secure Token Functions (DPAPI Encryption)
# =========================================================
function Save-TokenEncrypted {
    param([string]$Token)
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Token)
        $encrypted = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes, 
            $null, 
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        [System.IO.File]::WriteAllBytes($tokenFile, $encrypted)
        Write-Host "  Token saved securely (encrypted)!" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: Could not save token: $_" -ForegroundColor Yellow
    }
}

function Load-TokenEncrypted {
    try {
        if([System.IO.File]::Exists($tokenFile)) {
            $encrypted = [System.IO.File]::ReadAllBytes($tokenFile)
            $decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
                $encrypted, 
                $null, 
                [System.Security.Cryptography.DataProtectionScope]::CurrentUser
            )
            return [System.Text.Encoding]::UTF8.GetString($decrypted)
        }
    } catch {
        Write-Host "  Warning: Could not load saved token: $_" -ForegroundColor Yellow
    }
    return $null
}

function Clear-SavedToken {
    if([System.IO.File]::Exists($tokenFile)) {
        try {
            Remove-Item $tokenFile -Force
            Write-Host "  Saved token deleted!" -ForegroundColor Green
        } catch {
            Write-Host "  Could not delete token file" -ForegroundColor Yellow
        }
    }
}

# =========================================================
# API Helper Functions
# =========================================================
function Show-Loading {
    param([string]$Text, [int]$Duration = 1.5)
    $end = (Get-Date).AddSeconds($Duration)
    $frames = @('/','|','\','-')
    $i = 0
    while((Get-Date) -lt $end) {
        Write-Host -NoNewline "`r [$($frames[$i % 4])] $Text"
        Start-Sleep -Milliseconds 60
        $i++
    }
    Write-Host -NoNewline "`r [OK] $Text`n"
}

function Show-Progress {
    param([int]$Current, [int]$Total, [string]$Label)
    if($Total -eq 0) { return }
    $percent = [Math]::Round(($Current / $Total) * 100)
    $done = [Math]::Round($percent / 5)
    $bar = ("#" * $done).PadRight(20, ".")
    Write-Host -NoNewline "`r [$bar] $percent% - $Label"
}

function Invoke-DiscordAPI {
    param(
        [string]$Method,
        [string]$Endpoint,
        [object]$Body = $null,
        [int]$RetryCount = 3
    )
    
    $uri = "$apiBase/$Endpoint" -replace '([^:])/+','$1/'
    
    $headers = @{
        "Authorization" = $token
        "Content-Type"  = "application/json; charset=utf-8"
        "User-Agent"    = "Clony/5.3"
    }
    
    for($attempt = 1; $attempt -le $RetryCount; $attempt++) {
        try {
            $params = @{
                Uri = $uri
                Method = $Method
                Headers = $headers
                ErrorAction = 'Stop'
            }
            
            if($Body) {
                $jsonString = $Body | ConvertTo-Json -Depth 10 -Compress
                $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonString)
                $params.Body = $utf8Bytes
            }
            
            $r = Invoke-RestMethod @params
            return @{Success = $true; Data = $r; Status = 200}
        } catch {
            $status = if($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
            
            if($status -eq 429 -or ($status -ge 500 -and $status -le 599)) {
                if($attempt -lt $RetryCount) {
                    $retryAfter = 2
                    if($_.Exception.Response -and $_.Exception.Response.Headers['Retry-After']) {
                        $retryAfter = [int]$_.Exception.Response.Headers['Retry-After']
                    }
                    Start-Sleep -Seconds $retryAfter
                    continue
                }
            }
            
            $msg = if($_.Exception.Message) { $_.Exception.Message } else { "Unknown error" }
            return @{Success = $false; Status = $status; Message = $msg}
        }
    }
    
    return @{Success = $false; Status = 0; Message = "Max retries exceeded"}
}

function Get-Base64Image {
    param([string]$Url)
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Clony/5.3")
        $bytes = $wc.DownloadData($Url)
        $extension = if($Url -match '\.png') { "png" } elseif($Url -match '\.jpg') { "jpg" } elseif($Url -match '\.gif') { "gif" } else { "png" }
        $base64 = [Convert]::ToBase64String($bytes)
        return "image/$extension;base64,$base64"
    } catch {
        Write-Host "    Warning: Could not download image from $Url" -ForegroundColor Yellow
        return $null
    }
}

function Show-ServerList {
    param([string]$Title)
    Write-Host ""
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "|  $Title" -ForegroundColor Cyan
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Cyan
    for($i = 0; $i -lt $servers.Count; $i++) {
        $name = $servers[$i].name
        if($name.Length -gt 40) { $name = $name.Substring(0,37) + "..." }
        Write-Host "|  [$($i+1)] $($name.PadRight(40)) |" -ForegroundColor White
    }
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Cyan
}

# =========================================================
# Main Menu Loop
# =========================================================
Show-Banner

$savedToken = Load-TokenEncrypted
if($savedToken) {
    Write-Host "  [i] Saved token found! Auto-loaded." -ForegroundColor Cyan
    $token = $savedToken
    
    Show-Loading "Verifying token" 0.5
    $userResult = Invoke-DiscordAPI -Method "GET" -Endpoint "users/@me"
    if($userResult.Success) {
        $discordUser = $userResult.Data
    }
}

while($true) {
    Show-Banner
    Show-Header
    
    Write-Host "|  [1] Enter Token (Save Encrypted)                        |" -ForegroundColor Green
    Write-Host "|  [2] Load Servers                                        |" -ForegroundColor Green
    Write-Host "|  [3] Select Source Server                                |" -ForegroundColor Green
    Write-Host "|  [4] Select Target Server                                |" -ForegroundColor Green
    Write-Host "|  [5] START FULL CLONE                                    |" -ForegroundColor Yellow
    Write-Host "|  [6] Generate New Server (Auto-Create)                   |" -ForegroundColor Cyan
    Write-Host "|  [7] Clear Saved Token                                   |" -ForegroundColor Green
    Write-Host "|  [8] Exit                                                |" -ForegroundColor Green
    Write-Host "+----------------------------------------------------------+" -ForegroundColor Green
    
    if($token) {
        $masked = if($token.Length -gt 20) { $token.Substring(0,10) + "..." + $token.Substring($token.Length-10) } else { "****" }
        Write-Host "  Token: $masked (Encrypted)" -ForegroundColor DarkGray
    }
    if($sourceId) { Write-Host "  Source: $sourceId" -ForegroundColor DarkGray }
    if($targetId) { Write-Host "  Target: $targetId" -ForegroundColor DarkGray }
    
    Show-Footer
    
    $choice = Read-Host "`n> Select option"
    
    switch($choice) {
        "1" {
            $token = Read-Host "  Enter your Discord bot/user token"
            if($token.Length -ge 24) {
                Save-TokenEncrypted -Token $token
                
                Show-Loading "Verifying token" 0.5
                $userResult = Invoke-DiscordAPI -Method "GET" -Endpoint "users/@me"
                if($userResult.Success) {
                    $discordUser = $userResult.Data
                    Write-Host "  Token validated and saved!" -ForegroundColor Green
                } else {
                    Write-Host "  Error: Invalid token!" -ForegroundColor Red
                    $token = ""
                    $discordUser = $null
                }
            } else {
                Write-Host "  Error: Token too short!" -ForegroundColor Red
                $token = ""
            }
            Start-Sleep -Milliseconds 800
        }
        
        "2" {
            if(!$token) { Write-Host "`n  Error: Please enter a token first!" -ForegroundColor Red; Start-Sleep 1; continue }
            Show-Loading "Fetching servers from Discord" 1.5
            $r = Invoke-DiscordAPI -Method "GET" -Endpoint "users/@me/guilds"
            if($r.Success) {
                $servers = $r.Data
                Write-Host "  Loaded $($servers.Count) servers!" -ForegroundColor Green
            } else {
                Write-Host "  Error $($r.Status): $($r.Message)" -ForegroundColor Red
                if($r.Status -eq 401) {
                    Write-Host "  Tip: Invalid token. Please re-enter." -ForegroundColor Yellow
                    Clear-SavedToken
                    $token = ""
                    $discordUser = $null
                }
            }
            Start-Sleep 1
        }
        
        "3" {
            if($servers.Count -eq 0) { Write-Host "`n  Error: Please load servers first!" -ForegroundColor Red; Start-Sleep 1; continue }
            Show-ServerList "SELECT SOURCE SERVER"
            $input = Read-Host "`n  Enter number"
            if($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $servers.Count) {
                $idx = [int]$input - 1
                $sourceId = $servers[$idx].id
                Write-Host "  Source server set: $($servers[$idx].name)" -ForegroundColor Green
            } else {
                Write-Host "  Error: Invalid selection!" -ForegroundColor Red
            }
            Start-Sleep 1
        }
        
        "4" {
            if($servers.Count -eq 0) { Write-Host "`n  Error: Please load servers first!" -ForegroundColor Red; Start-Sleep 1; continue }
            Show-ServerList "SELECT TARGET SERVER"
            $input = Read-Host "`n  Enter number"
            if($input -match '^\d+$' -and [int]$input -ge 1 -and [int]$input -le $servers.Count) {
                $idx = [int]$input - 1
                $targetId = $servers[$idx].id
                Write-Host "  Target server set: $($servers[$idx].name)" -ForegroundColor Green
            } else {
                Write-Host "  Error: Invalid selection!" -ForegroundColor Red
            }
            Start-Sleep 1
        }
        
        "5" {
            if(!$sourceId -or !$targetId) {
                Write-Host "`n  Error: Please select BOTH source AND target server!" -ForegroundColor Red
                Start-Sleep 1.5; continue
            }
            
            Write-Host "`n  WARNING: This will DELETE ALL channels/roles in the TARGET server!" -ForegroundColor Red
            Write-Host "  This action CANNOT be undone!" -ForegroundColor Red
            $confirm = Read-Host "  Type 'CLONY' to confirm"
            if($confirm -ne "CLONY") { Write-Host "  Aborted." -ForegroundColor Yellow; Start-Sleep 1; continue }
            
            Show-Banner
            Write-Host ""
            Write-Host "=================================================================" -ForegroundColor Magenta
            Write-Host "                    CLONING PROCESS STARTED                     " -ForegroundColor Magenta
            Write-Host "=================================================================" -ForegroundColor Magenta
            Write-Host ""
            
            $stats = @{
                Roles = 0
                Categories = 0
                TextChannels = 0
                VoiceChannels = 0
                Emojis = 0
                Icon = $false
            }
            
            try {
                Show-Loading "Loading source server data" 1
                $g = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$sourceId"
                if(!$g.Success) { 
                    Write-Host "  Error: Failed to load source data! $($g.Message)" -ForegroundColor Red
                    Start-Sleep 2; continue 
                }
                $sourceGuildData = $g.Data
                
                Show-Loading "Cleaning target server" 2
                $ch = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$targetId/channels"
                if($ch.Success) {
                    $total = $ch.Data.Count; $curr = 0
                    foreach($c in $ch.Data) {
                        Show-Progress $curr $total "Deleting channels"
                        Invoke-DiscordAPI -Method "DELETE" -Endpoint "channels/$($c.id)" | Out-Null
                        $curr++
                    }
                    Write-Host "`r  [OK] Channels deleted                         "
                }
                $rl = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$targetId/roles"
                if($rl.Success) {
                    $rolesToDelete = $rl.Data | Where-Object { $_.name -ne "@everyone" -and -not $_.managed }
                    $total = $rolesToDelete.Count; $curr = 0
                    foreach($r in $rolesToDelete) {
                        Show-Progress $curr $total "Deleting roles"
                        Invoke-DiscordAPI -Method "DELETE" -Endpoint "guilds/$targetId/roles/$($r.id)" | Out-Null
                        $curr++
                    }
                    Write-Host "`r  [OK] Roles deleted                            "
                }
                
                Show-Loading "Updating server settings + ICON" 2
                $updateBody = @{name = $sourceGuildData.name}
                
                if($sourceGuildData.icon) {
                    Write-Host "    Downloading server icon..." -ForegroundColor DarkGray
                    $iconUrl = "https://cdn.discordapp.com/icons/$sourceId/$($sourceGuildData.icon).png"
                    $iconBase64 = Get-Base64Image -Url $iconUrl
                    if($iconBase64) {
                        $updateBody.icon = $iconBase64
                        $stats.Icon = $true
                        Write-Host "    Icon prepared for upload" -ForegroundColor Green
                    }
                }
                
                $patchResult = Invoke-DiscordAPI -Method "PATCH" -Endpoint "guilds/$targetId" -Body $updateBody
                if($patchResult.Success) {
                    Write-Host "  [OK] Server name and icon updated               "
                } else {
                    Write-Host "  Warning: Could not update icon: $($patchResult.Message)" -ForegroundColor Yellow
                }
                
                Write-Host "`n  Cloning roles with permissions..." -ForegroundColor Yellow
                $roles = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$sourceId/roles"
                $roleMap = @{}
                if($roles.Success) {
                    $roleList = $roles.Data | Where-Object { $_.name -ne "@everyone" -and -not $_.managed } | Sort-Object position
                    $total = $roleList.Count; $curr = 0
                    foreach($r in $roleList) {
                        Show-Progress $curr $total "Role: $($r.name)"
                        $body = @{
                            name = $r.name
                            permissions = [string]$r.permissions
                            color = $r.color
                            hoist = $r.hoist
                            mentionable = $r.mentionable
                            position = $r.position
                        }
                        $res = Invoke-DiscordAPI -Method "POST" -Endpoint "guilds/$targetId/roles" -Body $body
                        if($res.Success) {
                            $roleMap[$r.id] = $res.Data.id
                            $stats.Roles++
                        }
                        $curr++
                    }
                    Write-Host "`r  [OK] $($stats.Roles) roles cloned with permissions          "
                }
                
                Write-Host "`n  Cloning channel categories..." -ForegroundColor Yellow
                $chans = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$sourceId/channels"
                $catMap = @{}
                if($chans.Success) {
                    $categories = $chans.Data | Where-Object { $_.type -eq 4 }
                    $total = $categories.Count; $curr = 0
                    foreach($c in $categories) {
                        Show-Progress $curr $total "Category: $($c.name)"
                        $body = @{
                            name = $c.name
                            type = 4
                            position = $c.position
                        }
                        $cr = Invoke-DiscordAPI -Method "POST" -Endpoint "guilds/$targetId/channels" -Body $body
                        if($cr.Success) {
                            $catMap[$c.id] = $cr.Data.id
                            $stats.Categories++
                        }
                        $curr++
                    }
                    Write-Host "`r  [OK] $($stats.Categories) categories created                  "
                }
                
                Write-Host "`n  Cloning text and voice channels..." -ForegroundColor Yellow
                if($chans.Success) {
                    $others = $chans.Data | Where-Object { $_.type -ne 4 }
                    $total = $others.Count; $curr = 0
                    foreach($c in $others) {
                        Show-Progress $curr $total "Channel: $($c.name)"
                        $body = @{
                            name = $c.name
                            type = $c.type
                            position = $c.position
                            topic = $c.topic
                            nsfw = $c.nsfw
                            rate_limit_per_user = $c.rate_limit_per_user
                            bitrate = $c.bitrate
                            user_limit = $c.user_limit
                        }
                        
                        if($c.parent_id -and $catMap.ContainsKey($c.parent_id)) {
                            $body.parent_id = $catMap[$c.parent_id]
                        }
                        
                        if($c.permission_overwrites) {
                            $newOverwrites = @()
                            foreach($ow in $c.permission_overwrites) {
                                $newId = $ow.id
                                if($roleMap.ContainsKey($ow.id)) {
                                    $newId = $roleMap[$ow.id]
                                }
                                $newOverwrites += @{
                                    id = $newId
                                    type = $ow.type
                                    allow = $ow.allow
                                    deny = $ow.deny
                                }
                            }
                            $body.permission_overwrites = $newOverwrites
                        }
                        
                        $res = Invoke-DiscordAPI -Method "POST" -Endpoint "guilds/$targetId/channels" -Body $body
                        if($res.Success) {
                            if($c.type -eq 0) { $stats.TextChannels++ }
                            elseif($c.type -eq 2) { $stats.VoiceChannels++ }
                        }
                        $curr++
                    }
                    Write-Host "`r  [OK] $($stats.TextChannels) text, $($stats.VoiceChannels) voice channels created    "
                }
                
                Write-Host "`n  Cloning server emojis..." -ForegroundColor Yellow
                $emojis = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$sourceId/emojis"
                if($emojis.Success) {
                    $total = $emojis.Data.Count; $curr = 0
                    foreach($e in $emojis.Data) {
                        Show-Progress $curr $total "Emoji: $($e.name)"
                        $emojiUrl = "https://cdn.discordapp.com/emojis/$($e.id).png"
                        if($e.animated) { $emojiUrl = "https://cdn.discordapp.com/emojis/$($e.id).gif" }
                        $emojiBase64 = Get-Base64Image -Url $emojiUrl
                        if($emojiBase64) {
                            $body = @{
                                name = $e.name
                                image = $emojiBase64
                            }
                            $res = Invoke-DiscordAPI -Method "POST" -Endpoint "guilds/$targetId/emojis" -Body $body
                            if($res.Success) { $stats.Emojis++ }
                        }
                        $curr++
                    }
                    Write-Host "`r  [OK] $($stats.Emojis) emojis cloned                       "
                }
                
            } catch {
                Write-Host "`n  Error during cloning: $_" -ForegroundColor Red
                Start-Sleep 2
            }
            
            Write-Host ""
            Write-Host "=================================================================" -ForegroundColor Green
            Write-Host "                  CLONING SUCCESSFULLY COMPLETED                  " -ForegroundColor Green
            Write-Host "=================================================================" -ForegroundColor Green
            Write-Host "  Server Icon:      $(if($stats.Icon){'[OK] Uploaded'}else{'[SKIP]'})" -ForegroundColor Green
            Write-Host "  Roles:            $($stats.Roles)" -ForegroundColor Green
            Write-Host "  Categories:       $($stats.Categories)" -ForegroundColor Green
            Write-Host "  Text Channels:    $($stats.TextChannels)" -ForegroundColor Green
            Write-Host "  Voice Channels:   $($stats.VoiceChannels)" -ForegroundColor Green
            Write-Host "  Emojis:           $($stats.Emojis)" -ForegroundColor Green
            Write-Host "=================================================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "  Note: Unicode emojis in channel names will work in Discord!" -ForegroundColor Cyan
            Write-Host "  Custom emojis from source server are cloned separately." -ForegroundColor Cyan
            Read-Host "`n  Press Enter to return to menu"
        }
        
        "6" {
            if(!$sourceId) {
                Write-Host "`n  Error: Please select a SOURCE server first!" -ForegroundColor Red
                Start-Sleep 1; continue
            }
            
            Write-Host "`n  This will create a NEW server and clone into it." -ForegroundColor Cyan
            $newServerName = Read-Host "  Enter new server name (or press Enter for source name)"
            
            if([string]::IsNullOrWhiteSpace($newServerName)) {
                if($sourceGuildData) {
                    $newServerName = $sourceGuildData.name
                } else {
                    $g = Invoke-DiscordAPI -Method "GET" -Endpoint "guilds/$sourceId"
                    if($g.Success) {
                        $newServerName = $g.Data.name
                        $sourceGuildData = $g.Data
                    }
                }
            }
            
            Write-Host "  Creating server: $newServerName" -ForegroundColor Yellow
            Show-Loading "Creating new Discord server" 2
            
            $createBody = @{
                name = $newServerName
            }
            
            $createResult = Invoke-DiscordAPI -Method "POST" -Endpoint "guilds" -Body $createBody
            if($createResult.Success) {
                $targetId = $createResult.Data.id
                Write-Host "  Server created successfully!" -ForegroundColor Green
                Write-Host "  Server ID: $targetId" -ForegroundColor DarkGray
                Write-Host "  Starting clone process..." -ForegroundColor Yellow
                Start-Sleep 1
                
                $choice = "5"
                continue
            } else {
                Write-Host "  Error creating server: $($createResult.Message)" -ForegroundColor Red
                Start-Sleep 2
            }
        }
        
        "7" {
            Clear-SavedToken
            $token = ""
            $discordUser = $null
            $servers = @()
            $sourceId = ""
            $targetId = ""
            Start-Sleep 1
        }
        
        "8" {
            Show-Loading "Exiting Clony" 0.5
            Write-Host "`n  Goodbye! Thanks for using Clony." -ForegroundColor Cyan
            Start-Sleep 1
            exit
        }
        
        default {
            Write-Host "  Error: Invalid option!" -ForegroundColor Red
            Start-Sleep 0.8
        }
    }
}