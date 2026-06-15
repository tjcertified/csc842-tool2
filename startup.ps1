# Check for Admin

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
        if ($Toolname -eq "openssl") {
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") + ";" + "C:\Program Files\OpenSSL-Win64\bin\"
        }
    }
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

Install-Tool "openssl" "ShiningLight.OpenSSL.Dev"

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

$env:COSIGN_PASSWORD=""
cosign generate-key-pair


#Write-Host "[+] Creating root CA for Policy Controller"
#openssl ecparam -genkey -name secp384r1 | openssl ec -out rootCA.key
#openssl req -x509 -config local.cnf -new -nodes -key rootCA.key -sha256 -days 3650 -out rootCA.crt
#openssl ecparam -genkey -name prime256v1 -noout -out localhost.key
#openssl req -new -config ./local.cnf -key localhost.key -out localhost.csr
#Write-Host "[+] Verifying details for localhost.csr" -ForegroundColor Green
#openssl req -in localhost.csr -noout -text
#openssl x509 -req -in localhost.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out localhost.crt -days 397 -sha256 -extfile local.cnf -extensions req_ext
#Write-Host "[+] Verifying details for localhost.crt" -ForegroundColor Green
#openssl x509 -in localhost.crt -text -noout
#openssl x509 -in localhost.crt -noout -ext subjectAltName

Write-Host "[+] Starting podman backend for kubernetes to use:" -ForegroundColor Blue
try {
    podman machine init
    podman machine start
} catch {
    Write-Error "Could not start podman, please check installation."
    exit 1
}

Write-Host "[+] Starting up minikube rootless environment with podman backend and helm ingress" -ForegroundColor Blue
try {
    minikube config set rootless true
    minikube start --driver=podman --container-runtime=containerd
    minikube addons enable ingress
} catch { 
    Write-Error "Could not start minikube, check installation."
    exit 1
}


Write-Host "[+] Pre-reqs complete! Setting up Sigstore Policy Controller inside Kubernetes to enforce SLSA compliance"
try {
    Write-Host "  - setting up cosign namespace..." -ForegroundColor Green
    kubectl create namespace cosign-system
    
    Write-Host "[+] Adding cosign key to kubernetes" -ForegroundColor Green
    kubectl create secret generic upstream-public-key --namespace cosign-system --from-file=cosign.pub=cosign.pub

    Write-Host "  - adding cosign repo to helm..." -ForegroundColor Green
    helm repo add sigstore https://sigstore.github.io/helm-charts
    helm repo update

    Write-Host "  - installing policy controller..." -ForegroundColor Green
    helm install policy-controller -n cosign-system sigstore/policy-controller --devel

    WriteHost "  - awaiting cluster for readiness..." -ForegroundColor Green
    kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-webhook;
    kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-policy-webhook;

    Write-Host "  - enforcing compliance in cluster" -ForegroundColor Green
    kubectl label namespace default policy.sigstore.dev/include=true
} catch {
    Write-Error "Sigstore setup failed. Check error and see if prerequisites exist."
}