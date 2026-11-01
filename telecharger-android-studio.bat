@echo off
:: ============================================================
::  Telecharger Android Studio  -  v2.0
::
::  - Detecte TOUT SEUL les dernieres versions a chaque lancement
::    (liste officielle tenue par JetBrains, liens officiels Google)
::  - Verifie l'empreinte SHA-256 du fichier telecharge
::  - Peut se mettre a jour lui-meme (voir SCRIPT_URL plus bas)
::  - Garde une copie de la liste : marche aussi hors ligne
::
::  Tout est dans ce seul fichier : la partie PowerShell est
::  rangee a la fin, apres la ligne #==PS==#
:: ============================================================
setlocal
set "SCRIPT_VERSION=2.0"

:: Lien "raw" vers la derniere version de CE fichier (GitHub, Gist...).
:: Laisse vide pour desactiver l'auto-update du script lui-meme.
:: Exemple : https://raw.githubusercontent.com/PSEUDO/scripts/main/telecharger-android-studio.bat
set "SCRIPT_URL=https://github.com/CFTREZAWD/android-studio-downloader/edit/main/telecharger-android-studio.bat"

title Telecharger Android Studio
color 0B

set "AS_SELF=%~f0"
set "AS_VERSION=%SCRIPT_VERSION%"
set "AS_URL=%SCRIPT_URL%"
set "AS_NEW=%TEMP%\telecharger-android-studio.new.bat"

if /i "%~1"=="--updated" goto app
if not defined SCRIPT_URL goto app

:: ---- 1) Le script verifie s'il existe une version plus recente de lui-meme
set "AS_MODE=selfupdate"
call :runps
if not "%errorlevel%"=="10" goto app
echo.
echo   Nouvelle version du script installee, redemarrage...
timeout /t 2 >nul
:: Tout sur une seule ligne : cmd a deja lu la ligne avant que le fichier change
(copy /y "%AS_NEW%" "%~f0" >nul & del "%AS_NEW%" >nul 2>&1 & "%~f0" --updated & exit /b)

:app
:: ---- 2) Menu + telechargement (partie PowerShell en bas du fichier)
set "AS_MODE=app"
call :runps
endlocal
exit /b

:runps
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:AS_SELF); iex $s.Substring($s.LastIndexOf('#==PS==#'))"
exit /b %errorlevel%

#==PS==#
# ------------------------------------------------------------
#  Partie PowerShell (jamais lue par cmd, lancee par :runps)
# ------------------------------------------------------------
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ============ MODE 1 : auto-update du script ============
if ($env:AS_MODE -eq 'selfupdate') {
    try {
        Write-Host ''
        Write-Host '  Recherche d''une mise a jour du script...' -ForegroundColor DarkCyan
        $txt = (Invoke-WebRequest -Uri $env:AS_URL -UseBasicParsing -TimeoutSec 8).Content
        if ($txt -is [byte[]]) { $txt = [Text.Encoding]::UTF8.GetString($txt) }
        $m = [regex]::Match($txt, 'set "SCRIPT_VERSION=([0-9]+\.[0-9.]+)"')
        $ok = $m.Success -and $txt.TrimStart().StartsWith('@echo off') -and $txt.Contains('#==PS==#')
        if ($ok -and ([version]$m.Groups[1].Value -gt [version]$env:AS_VERSION)) {
            # Fins de ligne Windows obligatoires, sinon les "goto" d'un .bat cassent
            $txt = $txt -replace "`r?`n", "`r`n"
            [IO.File]::WriteAllText($env:AS_NEW, $txt, (New-Object Text.ASCIIEncoding))
            Write-Host ("  Version " + $m.Groups[1].Value + " trouvee (tu as la " + $env:AS_VERSION + ").") -ForegroundColor Green
            exit 10
        }
    } catch {
        Write-Host '  (Impossible de verifier la mise a jour du script, on continue.)' -ForegroundColor DarkGray
    }
    exit 0
}

# ============ MODE 2 : le telechargeur ============
$JsonUrl   = 'https://jb.gg/android-studio-releases-list.json'
$Archives  = 'https://developer.android.com/studio/archive'
$Dest      = Join-Path $env:USERPROFILE 'Downloads'
$CacheDir  = Join-Path $env:LOCALAPPDATA 'telecharger-android-studio'
$CacheFile = Join-Path $CacheDir 'releases.json'
$script:Source = ''

function Show-Header([string]$titre) {
    Clear-Host
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host ('     ' + $titre) -ForegroundColor Cyan
    Write-Host '  ============================================================' -ForegroundColor Cyan
    Write-Host ''
}

function Get-WinExe($item) {
    $item.download | Where-Object { $_.link -like '*-windows.exe' } | Select-Object -First 1
}

function Get-ShortName($item) {
    ($item.name -replace '^Android Studio\s*', '') -replace '\s*\|\s*', ' - '
}

function Get-Size($dl) {
    if ($dl.size) { return ($dl.size -replace 'GB', 'Go' -replace 'MB', 'Mo') }
    return '?'
}

function Load-Releases {
    Show-Header 'TELECHARGEUR ANDROID STUDIO'
    Write-Host '  Recherche des dernieres versions...' -ForegroundColor DarkCyan
    $raw = $null
    try {
        $raw = (Invoke-WebRequest -Uri $JsonUrl -UseBasicParsing -TimeoutSec 25).Content
        if ($raw -is [byte[]]) { $raw = [Text.Encoding]::UTF8.GetString($raw) }
        New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
        [IO.File]::WriteAllText($CacheFile, $raw)
        $script:Source = 'a jour (en ligne)'
    } catch {
        if (Test-Path $CacheFile) {
            $raw = [IO.File]::ReadAllText($CacheFile)
            $date = (Get-Item $CacheFile).LastWriteTime.ToString('dd/MM/yyyy HH:mm')
            $script:Source = "HORS LIGNE - liste du $date"
        }
    }
    if (-not $raw) { return @() }

    $liste = @()
    foreach ($it in ($raw | ConvertFrom-Json).content.item) {
        if (-not (Get-WinExe $it)) { continue }
        try { $v = [version]$it.version } catch { continue }
        $it | Add-Member -NotePropertyName V -NotePropertyValue $v -Force
        $liste += $it
    }
    # Le meme build apparait parfois deux fois dans la liste : on enleve les doublons
    $liste | Sort-Object V -Descending | Group-Object version | ForEach-Object { $_.Group[0] }
}

function Pick-Latest($liste, [string[]]$canaux) {
    $liste | Where-Object { $canaux -contains $_.channel } | Sort-Object V -Descending | Select-Object -First 1
}

function Test-Sha256([string]$fichier, [string]$attendu) {
    if (-not $attendu) { return $true }
    Write-Host '  Verification de l''empreinte SHA-256 (quelques secondes)...' -ForegroundColor DarkCyan
    $h = (Get-FileHash -Path $fichier -Algorithm SHA256).Hash
    return ($h -ieq $attendu)
}

function Offer-Launch([string]$fichier) {
    Write-Host ''
    Write-Host ('  Fichier : ' + $fichier) -ForegroundColor Gray
    Write-Host ''
    $r = Read-Host '   Lancer l''installateur maintenant ? (o/n)'
    if ($r -match '^[oO]') { Start-Process -FilePath $fichier }
}

function Download-Item($item) {
    $dl = Get-WinExe $item
    $nom = [IO.Path]::GetFileName($dl.link)
    $fichier = Join-Path $Dest $nom
    $part = $fichier + '.part'

    Show-Header ('Telechargement : ' + (Get-ShortName $item))
    if (-not (Test-Path $Dest)) { New-Item -ItemType Directory -Force -Path $Dest | Out-Null }

    # Deja telecharge et intact ? Pas besoin de recommencer.
    if (Test-Path $fichier) {
        Write-Host '  Ce fichier est deja dans tes Telechargements.' -ForegroundColor Yellow
        if (Test-Sha256 $fichier $dl.checksum) {
            Write-Host '  Fichier intact, pas besoin de le retelecharger !' -ForegroundColor Green
            Offer-Launch $fichier
            return
        }
        Write-Host '  Fichier abime, on le retelecharge.' -ForegroundColor Yellow
        Remove-Item $fichier -Force
    }

    $resp = $null; $stream = $null; $fs = $null
    try {
        Write-Host '  Connexion au serveur de Google...' -ForegroundColor DarkCyan
        $req = [Net.HttpWebRequest]::Create($dl.link)
        $req.UserAgent = 'Mozilla/5.0'
        $req.Timeout = 30000
        $req.ReadWriteTimeout = 60000
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object IO.FileStream($part, [IO.FileMode]::Create)
        $buffer = New-Object byte[] 262144
        $recu = 0
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $dernier = -1000
        $largeur = 40
        Write-Host ('  ' + $nom + '  (' + (Get-Size $dl) + ')') -ForegroundColor Yellow
        Write-Host ''
        while ($true) {
            $lu = $stream.Read($buffer, 0, $buffer.Length)
            if ($lu -le 0) { break }
            $fs.Write($buffer, 0, $lu)
            $recu += $lu
            $now = $sw.ElapsedMilliseconds
            if ((($now - $dernier) -gt 150) -or ($recu -eq $total)) {
                $dernier = $now
                $pct = 0
                if ($total -gt 0) { $pct = [math]::Floor(($recu / $total) * 100) }
                $plein = [math]::Floor(($largeur * $pct) / 100)
                $barre = ('#' * $plein) + ('.' * ($largeur - $plein))
                $sec = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
                $vitesse = ($recu / 1MB) / $sec
                $reste = ''
                if ($vitesse -gt 0 -and $total -gt 0) {
                    $s = [int](((($total - $recu) / 1MB) / $vitesse))
                    $reste = '  reste ' + [TimeSpan]::FromSeconds($s).ToString('mm\:ss')
                }
                $ligne = '  [' + $barre + '] ' + $pct + '%  ' + [math]::Round($recu / 1MB) + '/' + [math]::Round($total / 1MB) + ' Mo  (' + [math]::Round($vitesse, 1) + ' Mo/s)' + $reste + '    '
                Write-Host -NoNewline ("`r" + $ligne) -ForegroundColor Cyan
            }
        }
        $fs.Close(); $fs = $null
        Write-Host ''
        Write-Host ''
        if ($total -gt 0 -and $recu -ne $total) { throw 'Telechargement incomplet (connexion coupee ?).' }
        Move-Item -Path $part -Destination $fichier -Force

        if (Test-Sha256 $fichier $dl.checksum) {
            Write-Host '  Telechargement termine et verifie avec succes !' -ForegroundColor Green
            Offer-Launch $fichier
        } else {
            Remove-Item $fichier -Force
            Write-Host '  [!] L''empreinte ne correspond pas : fichier supprime. Reessaie.' -ForegroundColor Red
        }
    } catch {
        Write-Host ''
        Write-Host ('  [!] ERREUR : ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '      Verifie ta connexion internet puis reessaie.' -ForegroundColor Red
    } finally {
        if ($fs) { $fs.Close() }
        if ($stream) { $stream.Close() }
        if ($resp) { $resp.Close() }
        if (Test-Path $part) { Remove-Item $part -Force -ErrorAction SilentlyContinue }
    }
    Write-Host ''
    [void](Read-Host '   Appuie sur Entree pour revenir au menu')
}

function Choose-Other($liste) {
    Show-Header 'LES 20 DERNIERES VERSIONS'
    $top = @($liste | Select-Object -First 20)
    for ($i = 0; $i -lt $top.Count; $i++) {
        $it = $top[$i]
        $col = 'White'
        if ($it.channel -eq 'Canary') { $col = 'DarkYellow' }
        elseif ($it.channel -in @('RC', 'Beta')) { $col = 'Magenta' }
        elseif ($it.channel -in @('Release', 'Patch')) { $col = 'Green' }
        $num = ('[' + ($i + 1) + ']').PadLeft(5)
        Write-Host ('  ' + $num + ' ' + (Get-ShortName $it).PadRight(34) + $it.channel.PadRight(9) + $it.date) -ForegroundColor $col
    }
    Write-Host ''
    $r = Read-Host '   Numero de la version (Entree = retour)'
    $n = 0
    if ([int]::TryParse($r, [ref]$n) -and $n -ge 1 -and $n -le $top.Count) {
        Download-Item $top[$n - 1]
    }
}

# ---------------- Programme principal ----------------
$liste = @(Load-Releases)

while ($true) {
    $stable = Pick-Latest $liste @('Release', 'Patch')
    $preview = Pick-Latest $liste @('RC', 'Beta')
    $canary = Pick-Latest $liste @('Canary')
    # Une RC plus ancienne que la stable ne sert plus a rien
    if ($preview -and $stable -and $preview.V -le $stable.V) { $preview = $null }

    Show-Header ('TELECHARGEUR ANDROID STUDIO          script v' + $env:AS_VERSION)
    if ($liste.Count -eq 0) {
        Write-Host '  [!] Impossible de recuperer la liste des versions' -ForegroundColor Red
        Write-Host '      (pas de connexion et aucune copie enregistree).' -ForegroundColor Red
        Write-Host ''
        Write-Host '     [5] Ouvrir la page des archives dans le navigateur'
        Write-Host '     [6] Reessayer'
        Write-Host '     [7] Quitter'
    } else {
        Write-Host ('  Liste des versions : ' + $script:Source) -ForegroundColor DarkGray
        Write-Host ''
        Write-Host '  Choisis la version a telecharger :'
        Write-Host ''
        if ($stable) {
            Write-Host -NoNewline '     [1] Stable    - ' ; Write-Host -NoNewline (Get-ShortName $stable).PadRight(30) -ForegroundColor Green
            Write-Host ('(recommandee, ' + (Get-Size (Get-WinExe $stable)) + ')')
        }
        if ($preview) {
            Write-Host -NoNewline '     [2] RC/Beta   - ' ; Write-Host -NoNewline (Get-ShortName $preview).PadRight(30) -ForegroundColor Magenta
            Write-Host '(bientot stable)'
        } else {
            Write-Host '     [2] RC/Beta   - aucune en ce moment (la stable est plus recente)' -ForegroundColor DarkGray
        }
        if ($canary) {
            Write-Host -NoNewline '     [3] Canary    - ' ; Write-Host -NoNewline (Get-ShortName $canary).PadRight(30) -ForegroundColor DarkYellow
            Write-Host '(derniere nouveaute, instable)'
        }
        Write-Host '     [4] Autres versions (liste des 20 dernieres)'
        Write-Host '     [5] Ouvrir la page des archives dans le navigateur'
        Write-Host '     [6] Actualiser la liste'
        Write-Host '     [7] Quitter'
    }
    Write-Host ''
    Write-Host '  ------------------------------------------------------------'
    Write-Host ''
    $choix = Read-Host '   Ton choix (1-7)'

    switch ($choix) {
        '1' { if ($stable) { Download-Item $stable } }
        '2' { if ($preview) { Download-Item $preview } }
        '3' { if ($canary) { Download-Item $canary } }
        '4' { if ($liste.Count -gt 0) { Choose-Other $liste } }
        '5' { Start-Process $Archives }
        '6' { $liste = @(Load-Releases) }
        '7' { exit 0 }
        default {
            Write-Host ''
            Write-Host '  [!] Choix invalide, reessaie.' -ForegroundColor Red
            Start-Sleep -Seconds 2
        }
    }
}
