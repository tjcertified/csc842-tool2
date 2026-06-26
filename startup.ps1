# Check for Admin
function Test-AdminPrivileges {
    $currentUser = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent());
    if ($currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        return $true
    } else {
        return $false
    }
}

function Update-PathVariable {
    Write-Host "  - Refreshing PATH after install" -ForegroundColor Yellow
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Install-Tool {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Toolname,
        [Parameter(Mandatory=$true)]
        [string]$Packagename
    )

    Write-Host "[+] Checking for ${Toolname}:" -ForegroundColor Blue
    if (Get-Command $Toolname -ErrorAction SilentlyContinue) {
        Write-Host "  - $Toolname installed!" -ForegroundColor Green
    } else {
        Write-Host "  - $Toolname not found, installing via winget:" -ForegroundColor Yellow
        winget install --id $Packagename -e --silent --accept-source-agreements --accept-package-agreements

        Update-PathVariable
    }
}

# function Start-RootfulPodman {
#     Write-Host "[+] Check if podman is running..." -ForegroundColor Blue
#     try {
#         # See if podman is currently running
#         $podman_status = $(podman machine inspect --format "{{.State}}")
#         if ($podman_status -eq "running") {
#             Write-Host "  - podman started, stopping to guarantee rootful mode" -ForegroundColor Yellow
#             podman machine stop
#         }
#         Write-Host "  - starting podman in rootful mode for minikube success..." -ForegroundColor Green
#         podman machine set --rootful
#         podman machine start
#     } catch {
#         try {
#             # If it fails, try to init then start
#             podman machine init
#             Write-Host "  - starting podman in rootful mode for minikube success..." -ForegroundColor Green
#             podman machine set --rootful
#             podman machine start
#         } catch {
#             Write-Error "Could not start podman, please check installation and/or errors above."
#             exit 1
#         }
#     }
# }

Write-Host "[+] Checking for Administrator:" -ForegroundColor Blue
if (Test-AdminPrivileges) {
    Write-Host "  - continuing in Administrator session" -ForegroundColor Green
} else {
    Write-Host "  - This script requires admin mode. Please open a new PowerShell environment with Administrator privileges." -ForegroundColor Yellow
    exit 1
}

Write-Host "[+] Checking for WSL:" -ForegroundColor Blue
wsl --status *>&1 > $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  - WSL Installed" -ForegroundColor Green
} else {
    Write-Host "  - Installing WSL" -ForegroundColor Yellow
    wsl --install

    Update-PathVariable
}

Install-Tool "podman" "Redhat.Podman"

Install-Tool "jq" "jqlang.jq"

Install-Tool "mkcert" "FiloSottile.mkcert"

Install-Tool "kubectl" "Kubernetes.kubectl"

Install-Tool "minikube" "Kubernetes.minikube"

Install-Tool "helm" "Helm.Helm"

Install-Tool "gpg" "GnuPG.GnuPG"

Install-Tool "docker" "Docker.DockerDesktop"

Write-Host "[+] Checking for cosign:" -ForegroundColor Blue
if (Get-Command cosign -ErrorAction SilentlyContinue) {
    Write-Host "  - cosign found!" -ForegroundColor Green
} else {
    Write-Host "  - cosign not found, installing via winget:" -ForegroundColor Yellow
    winget install --id Sigstore.Cosign -e --silent --accept-source-agreements --accept-package-agreements

    Update-PathVariable

    # Fix badly named cosign for windows
    $old_cosign = (get-command cosign-windows-amd64.exe).Path
    $tmp_cosign = Split-Path -Path $old_cosign
    New-Item -Path $tmp_cosign\cosign.exe -ItemType SymbolicLink -Value $old_cosign
}

#Start-RootfulPodman

Write-Host "[+] (Re)Starting minikube..." -ForegroundColor Blue
try {
    minikube stop
    # minikube config set rootless true
    minikube start --driver=podman --container-runtime=containerd  --cert-expiration=26280h0m0s --cpus=4 --memory=16384
    #minikube start --driver=docker  --cert-expiration=26280h0m0s --cpus=4 --memory=16384
} catch { 
    Write-Error "Could not start minikube, check installation."
    exit 1
}

Write-Host "[+] Startup complete! You now have a working local kubernetes deployed with security tools, ready to secure." -ForegroundColor Blue