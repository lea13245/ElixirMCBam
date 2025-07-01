$ErrorActionPreference = "SilentlyContinue"

function Get-Signature {
    [CmdletBinding()]
    param (
        [string[]]$FilePath
    )

    $Existence = Test-Path -PathType "Leaf" -Path $FilePath
    $Authenticode = (Get-AuthenticodeSignature -FilePath $FilePath -ErrorAction SilentlyContinue).Status
    $Signature = "Firma inválida (UnknownError)"

    if ($Existence) {
        switch ($Authenticode) {
            "Valid"        { $Signature = "Firma válida" }
            "NotSigned"    { $Signature = "No está firmado" }
            "HashMismatch" { $Signature = "Hash no coincide" }
            "NotTrusted"   { $Signature = "No es de confianza" }
            default        { $Signature = "Firma inválida ($Authenticode)" }
        }
    } else {
        $Signature = "Archivo no encontrado"
    }

    return $Signature
}

Clear-Host

Write-Host ""
Write-Host ""
Write-Host ""
Write-Host -ForegroundColor Magenta "
██╗░░░░░██╗░░░██╗██╗░░░██╗██╗░░░░░░███████╗██╗░░░░░██╗░░██╗██████╗░
██║░░░░░██║░░░██║██║░░░██║██║░░░░░░██╔════╝██║░░░░░╚██╗██╔╝██╔══██╗
██║░░░░░██║░░░██║╚██╗░██╔╝██║█████╗█████╗░░██║░░░░░░╚███╔╝░██████╔╝
██║░░░░░██║░░░██║░╚████╔╝░██║╚════╝██╔══╝░░██║░░░░░░██╔██╗░██╔══██╗
███████╗╚██████╔╝░░╚██╔╝░░██║░░░░░░███████╗███████╗██╔╝╚██╗██║░░██║
╚══════╝░╚═════╝░░░░╚═╝░░░╚═╝░░░░░░╚══════╝╚══════╝╚═╝░░╚═╝╚═╝░░╚═╝"

Write-Host ""
Write-Host -ForegroundColor Pink " https://discord.gg/elixirmc - Tranquilo, estás en manos de expertos - bmseey"
Write-Host ""

# Verificar privilegios de administrador
function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}
if (-not (Test-Admin)) {
    Write-Warning "¡Debes ejecutar este script como Administrador!"
    Start-Sleep 10
    Exit
}

$sw = [Diagnostics.Stopwatch]::StartNew()

# Montar registro
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
        Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$ii\UserSettings\" |
            Select-Object -ExpandProperty PSChildName
    }
} catch {
    Write-Warning "Error parseando BAM Key. Probablemente tu versión de Windows no es compatible."
    Exit
}

$rpath = @(
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\",
    "HKLM:\SYSTEM\CurrentControlSet\Services\bam\state\"
)

# Obtener configuración de zona horaria
$UserTime = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").TimeZoneKeyName
$UserBias = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").ActiveTimeBias
$UserDay = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\TimeZoneInformation").DaylightBias

# Extraer entradas BAM
$Bam = foreach ($Sid in $Users) {
    foreach ($rp in $rpath) {
        $BamItems = Get-Item -Path "$rp\UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Property
        Write-Host -ForegroundColor Green "Extrayendo " -NoNewLine
        Write-Host -ForegroundColor Blue "$rp\UserSettings\$Sid"

        try {
            $objSID = New-Object System.Security.Principal.SecurityIdentifier($Sid)
            $User = $objSID.Translate([System.Security.Principal.NTAccount]).Value
        } catch {
            $User = ""
        }

        foreach ($Item in $BamItems) {
            $Key = Get-ItemProperty -Path "$rp\UserSettings\$Sid" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Item
            if ($Key.Length -eq 24) {
                $Hex = [System.BitConverter]::ToString($Key[7..0]) -replace "-", ""
                $TimeLocal = Get-Date ([DateTime]::FromFileTime([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $TimeUTC = Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))) -Format "yyyy-MM-dd HH:mm:ss"
                $Bias = -([convert]::ToInt32([Convert]::ToString($UserBias, 2), 2))
                $TImeUser = (Get-Date ([DateTime]::FromFileTimeUtc([Convert]::ToInt64($Hex, 16))).AddMinutes($Bias) -Format "yyyy-MM-dd HH:mm:ss")

                $f = Split-Path -Leaf $Item
                $cp = $Item.Substring(23)
                $path = Join-Path -Path "C:" -ChildPath $cp
                $sig = Get-Signature -FilePath $path

                [PSCustomObject]@{
                    'Tiempo del examinador'                         = $TimeLocal
                    'Tiempo de ultima ejecucion (UTC)'             = $TimeUTC
                    'Tiempo de ultima ejecucion (Hora del usuario)' = $TImeUser
                    'Aplicación'                                   = $f
                    'Ruta del archivo'                             = $path
                    'Firma digital'                                = $sig
                    'Usuario'                                      = $User
                    'SID'                                          = $Sid
                    'Ruta del registro'                            = $rp
                }
            }
        }
    }
}

$Bam | Out-GridView -PassThru -Title "Entradas BAM: $($Bam.Count) | Zona horaria: $UserTime"

$sw.Stop()
$t = [math]::Round($sw.Elapsed.TotalMinutes, 2)
Write-Host ""
Write-Host "⏱️ Tiempo total: $t minutos" -ForegroundColor Yellow
