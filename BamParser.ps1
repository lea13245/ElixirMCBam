$ErrorActionPreference = "SilentlyContinue"

function Get-Signature {
    [CmdletBinding()]
    param ([string[]]$FilePath)

    $Existence = Test-Path -PathType "Leaf" -Path $FilePath
    $Authenticode = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status
    if ($Existence) {
        switch ($Authenticode) {
            'Valid'         { return "Firma Válida" }
            'NotSigned'     { return "Firma Inválida (No está firmado)" }
            'HashMismatch'  { return "Firma Inválida (HashMismatch)" }
            'NotTrusted'    { return "Firma Inválida (No es de confianza)" }
            'UnknownError'  { return "Firma Inválida (Error desconocido)" }
            default         { return "Firma Inválida (Error desconocido)" }
        }
    } else {
        return "El archivo no fue encontrado"
    }
}

Clear-Host
Write-Host ""; Write-Host ""; Write-Host "Tranquilo, estás en manos de expertos"; Write-Host ""
Write-Host -ForegroundColor Magenta """
██╗░░░░░██╗░░░██╗██╗░░░██╗██╗░░░░░░███████╗██╗░░░░░██╗░░██╗██████╗░
██║░░░░░██║░░░██║██║░░░██║██║░░░░░░██╔════╝██║░░░░░╚██╗██╔╝██╔══██╗
██║░░░░░██║░░░██║╚██╗░██╔╝██║█████╗█████╗░░██║░░░░░░╚███╔╝░██████╔╝
██║░░░░░██║░░░██║░╚████╔╝░██║╚════╝██╔══╝░░██║░░░░░░██╔██╗░██╔══██╗
███████╗╚██████╔╝░░╚██╔╝░░██║░░░░░░███████╗███████╗██╔╝╚██╗██║░░██║
╚══════╝░╚═════╝░░░░╚═╝░░░╚═╝░░░░░░╚══════╝╚══════╝╚═╝░░╚═╝╚═╝░░╚═╝"""
Write-Host ""
Write-Host -ForegroundColor Pink " https://discord.gg/elixirmc - https://discord.gg/luvicraft - Tranquilo, estas en manos de expertos - bmseey"
Write-Host ""

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if (!(Test-Admin)) {
    Write-Warning "Abre PowerShell como administrador."
    Start-Sleep 10
    Exit
}

$sw = [Diagnostics.Stopwatch]::StartNew()

if (!(Get-PSDrive -Name HKLM -PSProvider Registry)) {
    Try { New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE }
    Catch { Write-Warning "Error montando HKEY_LOCAL_MACHINE" }
}

$bv = ("bam", "bam\State")
Try {
    $Users = foreach ($ii in $bv) {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ii\UserSettings\" | Select-Object -ExpandProperty PSChildName
    }
} Catch {
    Write-Warning "Error parseando BAM Key. Probablemente no soporta tu versión de Windows."
    Exit
}

$rpath = @("HKLM:\SYSTEM\CurrentControlSet\Services\bam\", "HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\")
$TimeInfo = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation"
$UserTime = $TimeInfo.TimeZoneKeyName
$UserBias = $TimeInfo.ActiveTimeBias
$UserDay = $TimeInfo.DaylightBias

$Bam = foreach ($Sid in $Users) {
    foreach ($rp in $rpath) {
        $BamItems = Get-Item -Path "$rp\UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        Write-Host -ForegroundColor Green "Extrayendo " -NoNewLine
        Write-Host -ForegroundColor Blue "$rp\UserSettings\$Sid"

        try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $User = $objSID.Translate([System.Security.Principal.NTAccount]).Value
        } catch { $User = "" }

        foreach ($Item in $BamItems) {
            $Key = Get-ItemProperty -Path "$rp\UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Item
            if ($Key.Length -eq 24) {
                $Hex = [System.BitConverter]::ToString($Key[7..0]) -replace "-", ""
                $TimeLocal = Get-Date ([DateTime]::FromFileTime([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $TimeUTC = Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $Bias = -([Convert]::ToInt32([Convert]::ToString($UserBias,2),2))
                $TimeUser = (Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))).AddMinutes($Bias)) -Format "yyyy-MM-dd HH:mm:ss"

                $parts = ($Item -split '\\')
                $d = if ($parts.Count -gt 3 -and $parts[3] -match '\d') { (Split-Path -Path $Item).Substring(23).TrimStart("\Device\HarddiskVolume") } else { "" }
                $f = if ($parts.Count -gt 3 -and $parts[3] -match '\d') { Split-Path -Leaf $Item.TrimStart() } else { $Item }
                $cp = if ($parts.Count -gt 3 -and $parts[3] -match '\d') { $Item.Remove(1,23) } else { "" }
                $path = if ($parts.Count -gt 3 -and $parts[3] -match '\d') { Join-Path -Path "C:" -ChildPath $cp } else { "" }
                $sig = if ($parts.Count -gt 3 -and $parts[3] -match '\d') { Get-Signature -FilePath $path } else { "" }

                [PSCustomObject]@{
                    "Tiempo del examinador" = $TimeLocal
                    "Tiempo de última ejecución (UTC)" = $TimeUTC
                    "Tiempo de última ejecución (Hora del usuario)" = $TimeUser
                    "Application" = $f
                    "Path" = $path
                    "Signature" = $sig
                    "User" = $User
                    "SID" = $Sid
                    "Regpath" = $rp
                }
            }
        }
    }
}

$Bam | Out-GridView -PassThru -Title "Entradas BAM: $($Bam.Count) - Zona Horaria del Usuario: ($UserTime)"

$sw.Stop()
$t = $sw.Elapsed.TotalMinutes
Write-Host ""
Write-Host "Se tardó $t minutos." -ForegroundColor Yellow
