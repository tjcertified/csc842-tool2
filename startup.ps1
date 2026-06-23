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

function Start-RootfulPodman {
    Write-Host "[+] Check if podman is running..." -ForegroundColor Blue
    try {
        # See if podman is currently running
        $podman_status = $(podman machine inspect --format "{{.State}}")
        if ($podman_status -eq "running") {
            Write-Host "  - podman started, stopping to guarantee rootful mode" -ForegroundColor Yellow
            podman machine stop
        }
        Write-Host "  - starting podman in rootful mode for minikube success..." -ForegroundColor Green
        podman machine set --rootful
        podman machine start
    } catch {
        try {
            # If it fails, try to init then start
            podman machine init
            Write-Host "  - starting podman in rootful mode for minikube success..." -ForegroundColor Green
            podman machine set --rootful
            podman machine start
        } catch {
            Write-Error "Could not start podman, please check installation and/or errors above."
            exit 1
        }
    }
}

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


if (-not (Test-Path -Path "./cosign.key") -and -not (Test-Path -Path "./cosign.pub")) {
    $env:COSIGN_PASSWORD="1234"
    $env:COSIGN_YES="true"
    Write-Host "[+] Generating cosign key-pair for signing artifacts." -ForegroundColor Blue
    cosign generate-key-pair
}

Write-Host "[+] Creating root CA for Policy Controller - NOTE: requires approval, click 'Yes' on prompt if it pops up" -ForegroundColor Blue
mkcert -install
New-Item -ItemType Directory -Force -Path ".\certs" | Out-Null
$env:CAROOT="$($pwd.Path)\certs"
mkcert.exe -cert-file="$env:CAROOT\tls.crt" -key-file="$env:CAROOT\tls.key" host.minikube.internal 127.0.0.1
$bytes = [System.IO.File]::ReadAllBytes("$env:CAROOT\rootCA.pem")
$b64String = [System.Convert]::ToBase64String($bytes)

Start-RootfulPodman

Write-Host "[+] (Re)Starting minikube rootless environment with podman backend and helm ingress" -ForegroundColor Blue
try {
    minikube stop
    # minikube config set rootless true
    minikube start --driver=podman --container-runtime=containerd --addons=ingress
} catch { 
    Write-Error "Could not start minikube, check installation."
    exit 1
}

Write-Host "[+] Pre-reqs complete! Setting up Kyverno inside Kubernetes to enforce signed containers." -ForegroundColor Blue
try {
    #Write-Host "  - setting up cosign namespace..." -ForegroundColor Green
    #kubectl create namespace cosign-system
    kubectl create namespace kyverno
    
    #Write-Host "  - Adding cosign key to kubernetes" -ForegroundColor Green
    #kubectl create secret generic upstream-public-key --namespace cosign-system --from-file=cosign.pub=cosign.pub

    #Write-Host "  - adding cosign repo to helm..." -ForegroundColor Green
    #helm repo add sigstore https://sigstore.github.io/helm-charts
    #helm repo update
    Write-Host "  - adding Kyverno repo to helm..." -ForegroundColor Green
    helm repo add kyverno https://kyverno.github.io/kyverno/
    helm repo update

    #Write-Host "  - installing policy controller..." -ForegroundColor Green
    #helm install policy-controller -n cosign-system sigstore/policy-controller --devel
    Write-Host "  - installing Kyverno..." -ForegroundColor Green
    helm install kyverno kyverno/kyverno -n kyverno
    

    #Write-Host "  - awaiting cluster for readiness..." -ForegroundColor Green
    #kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-webhook;
    #kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-policy-webhook;

    Write-Host "  - enforcing compliance in cluster" -ForegroundColor Green
    kubectl label namespace default policy.sigstore.dev/include=true
} catch {
    Write-Error "Sigstore setup failed. Check error and see if prerequisites exist. Removing environment"
    minikube delete    
    exit 1
}

Write-Host "[+] Starting minikube tunnel for ingress"
Start-Job -ScriptBlock { minikube tunnel } -Name "TunnelJob"
