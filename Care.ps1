#requires -Version 5.1
[CmdletBinding()]
param([switch]$DiagnoseOnly, [string]$Server = '', [string]$Restore = '')
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$admin = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Run Start.cmd as administrator (right-click). No changes made.'
    exit 1
}
$base = Join-Path $env:LOCALAPPDATA 'AmneziaCare'
$stamp = (Get-Date -Format yyyyMMdd-HHmmss) + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
$report = Join-Path $base "reports\$stamp"
New-Item -ItemType Directory -Path $report -Force | Out-Null
$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$encoding = [Text.Encoding]::GetEncoding(28591)
function Save-Check($Name, [scriptblock]$Action) {
    try { & $Action 2>&1 | Out-File (Join-Path $report "$Name.txt") -Encoding utf8 -Width 300 }
    catch { $_ | Out-File (Join-Path $report "$Name.txt") -Encoding utf8 }
}
function Probe([string]$Domain, [string]$IP = '') {
    $ErrorActionPreference = 'Continue'
    $argsList = @('-q','-4','--noproxy','*','--connect-timeout','4','--max-time','10','-sS','-o','NUL','-w','%{http_code}|%{remote_ip}|%{time_appconnect}|%{time_total}')
    if ($IP) { $argsList += @('--resolve', "${Domain}:443:$IP") }
    $argsList += "https://$Domain/"
    $raw = @(& curl.exe @argsList 2>&1)
    $exitCode = $LASTEXITCODE
    $parts = ([string]$raw[-1]).Split('|')
    $status = 0; $total = 0.0
    if ($parts.Count -eq 4) {
        [void][int]::TryParse($parts[0], [ref]$status)
        [void][double]::TryParse($parts[3], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$total)
    }
    [pscustomobject]@{ Domain=$Domain; RequestedIP=$IP; Exit=$exitCode; HTTP=$status; Total=$total; Raw=($raw -join "`n"); Usable=($exitCode -eq 0 -and $status -ge 200 -and $status -lt 400) }
}
if ($Restore) {
    $restorePath = [IO.Path]::GetFullPath($Restore)
    if (-not $restorePath.StartsWith([IO.Path]::GetFullPath((Join-Path $base 'backups')) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Restore accepts only AmneziaCare backups.' }
    Copy-Item $hostsPath (Join-Path $report 'hosts-before-restore.backup')
    Copy-Item -LiteralPath $restorePath -Destination $hostsPath -Force
    & ipconfig.exe /flushdns
    Write-Host "Restored: $restorePath"
    exit
}
Write-Host "Amnezia Care 1.0 | Report: $report" -ForegroundColor Cyan
Save-Check system { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,LastBootUpTime,FreePhysicalMemory; Get-Date; Get-Service W32Time }
Save-Check adapters { Get-NetAdapter | Select-Object Name,InterfaceIndex,Status,LinkSpeed,InterfaceDescription | Format-Table -AutoSize }
Save-Check addresses { Get-NetIPAddress | Select-Object InterfaceAlias,IPAddress,PrefixLength | Format-Table -AutoSize }
Save-Check routes { Get-NetRoute | Format-Table -AutoSize }
Save-Check dns { Get-DnsClientServerAddress | Format-List; Get-DnsClientNrptPolicy | Format-List }
Save-Check proxy { netsh winhttp show proxy; Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL }
Save-Check ipv6 { Get-NetAdapterBinding -ComponentID ms_tcpip6 | Format-Table -AutoSize }
Save-Check firewall { Get-NetFirewallProfile | Select-Object Name,Enabled,DefaultInboundAction,DefaultOutboundAction | Format-List }
Save-Check time { w32tm /query /status }
Save-Check tls { Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols' -ErrorAction Continue }
$vpn = @(Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Name -match 'Amnezia' })
$dnsServers = @()
foreach ($adapter in $vpn) { $dnsServers += @(Get-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4).ServerAddresses }
$original = [IO.File]::ReadAllBytes($hostsPath)
$text = $encoding.GetString($original)
$pattern = '(?im)^[ \t]*(?:45\.155\.204\.190|95\.182\.120\.241)[ \t]+((?:[a-z0-9-]+\.)*(?:chatgpt\.com|openai\.com|oaistatic\.com|oaiusercontent\.com|anthropic\.com|claude\.ai))\.?[ \t]*(?:#[^\r\n]*)?(?=\r?$)'
$matches = [regex]::Matches($text, $pattern)
$domains = @('chatgpt.com','claude.ai','api.openai.com','api.anthropic.com','gemini.google.com') + @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() })
$domains = @($domains | Sort-Object -Unique)
$approved = @{}; $results = @(); $normalBefore = @{}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is required. No hosts changes made.' }
foreach ($domain in $domains) {
    Write-Host "Checking $domain"
    $normal = Probe $domain
    $results += $normal; $normalBefore[$domain] = $normal
    try {
        [Net.Dns]::GetHostAddresses($domain) | ForEach-Object { "$domain system=$($_.IPAddressToString)" } | Add-Content (Join-Path $report 'resolution.txt')
        if ($dnsServers.Count -eq 0) { continue }
        $records = @(Resolve-DnsName -Name $domain -Type A -Server $dnsServers[0] -DnsOnly -NoHostsFile -QuickTimeout -ErrorAction Stop)
        $ip = @($records | Where-Object { $_.Type -eq 'A' -and $_.IPAddress -notin @('45.155.204.190','95.182.120.241') } | Select-Object -ExpandProperty IPAddress | Select-Object -First 1)
        if ($ip.Count -eq 0) { continue }
        $direct1 = Probe $domain $ip[0]; $direct2 = Probe $domain $ip[0]
        $results += $direct1; $results += $direct2
        if ($direct1.Usable -and $direct2.Usable -and ((-not $normal.Usable) -or ([Math]::Max($direct1.Total,$direct2.Total) -lt $normal.Total * 0.8))) { $approved[$domain] = $true }
    } catch { "$domain DNS/probe error: $_" | Add-Content (Join-Path $report 'errors.txt') }
}
$results | ConvertTo-Json -Depth 4 | Out-File (Join-Path $report 'https.json') -Encoding utf8
$changed = 0; $backup = ''
if (-not $DiagnoseOnly -and $approved.Count -gt 0 -and $vpn.Count -gt 0) {
    $updated = $text
    # Reverse order keeps original match offsets valid.
    for ($i=$matches.Count-1; $i -ge 0; $i--) {
        $m = $matches[$i]; $domain = $m.Groups[1].Value.ToLowerInvariant()
        if ($approved.ContainsKey($domain)) { $updated = $updated.Insert($m.Index, '# amnezia-care-disabled: '); $changed++ }
    }
    if ($changed -gt 0) {
        $backupDir = Join-Path $base 'backups'; New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backup = Join-Path $backupDir "hosts-$stamp.backup"
        Copy-Item -LiteralPath $hostsPath -Destination $backup
        # Refuse to overwrite another program's concurrent edit.
        if ($encoding.GetString([IO.File]::ReadAllBytes($hostsPath)) -cne $text) { throw 'hosts changed during diagnosis; no modification made.' }
        try {
            [IO.File]::WriteAllBytes($hostsPath,$encoding.GetBytes($updated))
            if ($encoding.GetString([IO.File]::ReadAllBytes($hostsPath)) -cne $updated) { throw 'Write verification failed.' }
            & ipconfig.exe /flushdns | Out-File (Join-Path $report 'dns-flush.txt') -Encoding utf8
            $post = @()
            foreach ($domain in @($matches | ForEach-Object { $_.Groups[1].Value.ToLowerInvariant() } | Sort-Object -Unique)) {
                if ($approved.ContainsKey($domain)) {
                    $test = Probe $domain; $post += $test
                    if (-not $test.Usable) { throw "Post-check failed: $domain. Rolling back hosts." }
                }
            }
            $post | ConvertTo-Json -Depth 4 | Out-File (Join-Path $report 'https-after.json') -Encoding utf8
        } catch {
            [IO.File]::WriteAllBytes($hostsPath,$original); & ipconfig.exe /flushdns | Out-Null
            "ROLLED BACK: $_" | Add-Content (Join-Path $report 'errors.txt'); $changed = 0
        }
    }
}
@("Matching active hosts lines: $($matches.Count)","Changed lines: $changed","Backup: $backup","VPN adapters: $($vpn.Count)","No universal IPv6/certificate/firewall repair is inferred.","HTTP 403 proves response, not working application. Review errors and JSON.","Report is local and may contain private addresses. Never publish raw reports.") | Out-File (Join-Path $report 'SUMMARY.txt') -Encoding utf8
# Optional read-only server check, using OpenSSH normally. Password never stored.
$configPath = Join-Path $base 'server.json'
if (-not $Server -and (Test-Path $configPath)) { $Server = (Get-Content $configPath -Raw | ConvertFrom-Json).Server }
if (-not $Server) { $Server = Read-Host 'SSH server user@host (Enter to skip; saved for next run)' }
if ($Server) {
    if ($Server -notmatch '^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$') { throw 'Expected user@host (no shell arguments).' }
    @{Server=$Server} | ConvertTo-Json | Out-File $configPath -Encoding utf8
    if ((Get-Command ssh.exe -ErrorAction SilentlyContinue) -and (Get-Command scp.exe -ErrorAction SilentlyContinue)) {
        $remote = "/tmp/amnezia-care-$stamp.sh"
        & scp.exe -o ConnectTimeout=10 (Join-Path $PSScriptRoot 'server-check.sh') "${Server}:$remote"
        if ($LASTEXITCODE -eq 0) {
            & ssh.exe -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=2 $Server "bash '$remote'; rc=`$?; rm -f '$remote'; exit `$rc" | Out-File (Join-Path $report 'server.txt') -Encoding utf8
            "SSH exit: $LASTEXITCODE" | Add-Content (Join-Path $report 'SUMMARY.txt')
        } else { 'SCP failed; server checks skipped.' | Add-Content (Join-Path $report 'SUMMARY.txt') }
    } else { 'OpenSSH missing; server checks skipped, no software installed.' | Add-Content (Join-Path $report 'SUMMARY.txt') }
}
Compress-Archive -Path "$report\*" -DestinationPath "$report.zip" -Force
Write-Host "Done. Changed hosts lines: $changed" -ForegroundColor Green
Write-Host "Report: $report.zip"
Write-Host "Backup: $backup"
Write-Host 'Restart browser/application to refresh existing connections.'


