$ErrorActionPreference = "SilentlyContinue"

function Get-Signature {
    [CmdletBinding()]
    param (
        [string[]]$FilePath
    )

    $Existence = Test-Path -PathType "Leaf" -Path $FilePath
    $Authenticode = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status
    $Signature = "Firma inválida (Error desconocido)"

    if ($Existence) {
        switch ($Authenticode) {
            "Valid"        { $Signature = "Firma válida" }
            "NotSigned"    { $Signature = "No está firmado" }
            "HashMismatch" { $Signature = "Firma inválida (HashMismatch)" }
            "NotTrusted"   { $Signature = "Firma inválida (No confiable)" }
            default        { $Signature = "Firma inválida ($Authenticode)" }
        }
    } else {
        $Signature = "Archivo no encontrado"
    }

    return $Signature
}

Clear-Host
Write-Host ""
Write-Host -ForegroundColor Magenta " 
██╗░░░░░██╗░░░██╗██╗░░░██╗██╗░░░░░░███████╗██╗░░░░░██╗░░██╗██████╗░
██║░░░░░██║░░░██║██║░░░██║██║░░░░░░██╔════╝██║░░░░░╚██╗██╔╝██╔══██╗
██║░░░░░██║░░░██║╚██╗░██╔╝██║█████╗█████╗░░██║░░░░░░╚███╔╝░██████╔╝
██║░░░░░██║░░░██║░╚████╔╝░██║╚════╝██╔══╝░░██║░░░░░░██╔██╗░██╔══██╗
███████╗╚██████╔╝░░╚██╔╝░░██║░░░░░░███████╗███████╗██╔╝╚██╗██║░░██║
╚══════╝░╚═════╝░░░░╚═╝░░░╚═╝░░░░░░╚══════╝╚══════╝╚═╝░░╚═╝╚═╝░░╚═╝" 
Write-Host ""
Write-Host -ForegroundColor Cyan "https://discord.gg/elixirmc - Tranquilo, estás en manos de expertos - bmseey"
Write-Host ""

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (!(Test-Admin)) {
    Write-Warning "Debes ejecutar como administrador"
    Start-Sleep 10
    Exit
}

$sw = [Diagnostics.Stopwatch]::StartNew()

if (!(Get-PSDrive -Name HKLM -PSProvider Registry)) {
    try {
        New-PSDrive -Name HKLM -PSProvider Registry -Root HKEY_LOCAL_MACHINE
    } catch {
        Write-Warning "Error montando HKEY_LOCAL_MACHINE"
    }
}

$bv = @("bam", "bam\State")
try {
    $Users = foreach ($ii in $bv) {
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($ii)\UserSettings\" | Select-Object -ExpandProperty PSChildName
    }
} catch {
    Write-Warning "Error leyendo claves BAM. Puede que tu versión de Windows no sea compatible."
    Exit
}

$rpath = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\",
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\"
)

$UserTime = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").TimeZoneKeyName
$UserBias = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").ActiveTimeBias
$UserDay  = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").DaylightBias

$Bam = foreach ($Sid in $Users) {
    foreach ($rp in $rpath) {
        $BamItems = Get-Item -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        Write-Host -ForegroundColor Green "Extrayendo" -NoNewLine
        Write-Host -ForegroundColor Blue " $($rp)UserSettings\$Sid"

        try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $User = $objSID.Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            $User = ""
        }

        foreach ($Item in $BamItems) {
            $Key = Get-ItemProperty -Path "$($rp)UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Item

            if ($Key.Length -eq 24) {
                $Hex = [System.BitConverter]::ToString($Key[7..0]) -replace "-", ""
                $TimeLocal = Get-Date ([DateTime]::FromFileTime([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $TimeUTC = Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $Bias = -([Convert]::ToInt32([Convert]::ToString($UserBias, 2), 2))
                $TImeUser = (Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))).AddMinutes($Bias) -Format "yyyy-MM-dd HH:mm:ss")

                $path = ""
                $f = ""
                if ($Item -match '\\Device\\HarddiskVolume') {
                    $cp = ($Item).Remove(1, 23)
                    $path = Join-Path -Path "C:" -ChildPath $cp
                    $f = Split-Path -Leaf $path
                }

                $sig = Get-Signature -FilePath $path

                [PSCustomObject]@{
                    'Tiempo del examinador'                         = $TimeLocal
                    'Tiempo de última ejecución (UTC)'              = $TimeUTC
                    'Tiempo de última ejecución (hora del usuario)' = $TImeUser
                    'Aplicación'                                    = $f
                    'Ruta del archivo'                              = $path
                    'Firma digital'                                 = $sig
                    'Usuario'                                       = $User
                    'SID'                                           = $Sid
                    'Ruta del registro'                             = $rp
                }
            }
        }
    }
}

$Bam | Out-GridView -PassThru -Title "Entradas BAM: $($Bam.Count) - Zona Horaria: $UserTime"

$sw.Stop()
Write-Host ""
Write-Host "Se tardó $($sw.Elapsed.TotalMinutes) minutos." -ForegroundColor Yellow
