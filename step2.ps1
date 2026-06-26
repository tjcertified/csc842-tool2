# Write-Host "[+] Ensure minikube is running..." -ForegroundColor Blue
# if (Get-Job -Name TunnelJob1 -ErrorAction SilentlyContinue)
# {
#     Stop-Job -Name TunnelJob
#     Remove-Job -Name TunnelJob
# }
# Start-Job -Name "TunnelJob" -ScriptBlock { minikube tunnel }

Write-Host "[+] Read PowerShell Data file for env vars..."
$data = Import-PowerShellDataFile -Path .\config.psd1
Write-Host "[+] Retrieved $($data.DockerUsername) , $($data.DockerToken ), $($data.DockerEmail)"

# Should check for empty vars here

Write-Host "[+] Enable Docker Hardened Images Catalog..." -ForegroundColor Blue
Write-Host "  - downloading key for Kyverno verification..." -ForegroundColor Green
Invoke-WebRequest -Uri "https://registry.scout.docker.com/keyring/dhi/latest.pub" -OutFile "dhi-latest.pub"

Write-Host "  - installing docker login secret into kubernetes..." -ForegroundColor Green
kubectl create namespace kyverno
kubectl create secret docker-registry dhi-pull-secret -n kyverno `
    --docker-server=dhi.io `
    --docker-username=$($data.DockerUsername) `
    --docker-password=$($data.DockerToken) `
    --docker-email=$($data.DockerEmail)

Write-Host "[+] Adding Kyverno for image verification in Kubernetes" -ForegroundColor Blue
# Write-Host "  - adding Kyverno repo to helm..." -ForegroundColor Green
# helm repo add kyverno https://kyverno.github.io/kyverno/
# helm repo update

Write-Output "$($data.DockerToken)" | helm registry login dhi.io -u "$($data.DockerUsername)" --password-stdin
Write-Host "  - installing Kyverno..." -ForegroundColor Blue
# helm install kyverno kyverno/kyverno `
#     --namespace kyverno --wait `
#     --set "image.pullSecrets[0].name=dhi-pull-secret" `
#     --set global.image.registry=dhi.io `
#     --set image.registry=dhi.io

# Working, but want to try dhi.io versoin
# helm install kyverno kyverno/kyverno --version 3.8.1 `
#     --namespace kyverno --create-namespace --wait `
#     --set initContainer.image.registry=dhi.io `
#     --set global.image.registry=dhi.io `
#     --set image.repository=kyverno/kyverno

helm install kyverno oci://dhi.io/kyverno-chart --version 3.8.1 `
    --namespace kyverno --create-namespace --wait --debug `
    --set "image.pullSecrets[0].name=dhi-pull-secret" `
     --set initContainer.image.registry=dhi.io `
     --set global.image.registry=dhi.io `
     --set image.repository=kyverno/kyverno

# kubectl create secret generic dhi-public-key --from-file=dhi-latest.pub=./dhi-latest.pub --namespace kyverno
# Write-Host "  - enforcing Docker Hardened Images via yaml policy file..." -ForegroundColor Blue
# kubectl apply -f ./dhi-validating-policy.yaml
# kubectl apply -f ./restrict-dhi-validatingpolicy.yaml

# Write-Host "[+] Installing valkey for gitlab..." -ForegroundColor Blue
# helm repo add valkey https://valkey.io/valkey-helm/
# helm repo update

helm install valkey oci://dhi.io/valkey-chart --version 0.10.0 `
    --namespace valkey --create-namespace --wait `
    --set "images.pullSecrets[0].name=dhi-pull-secret" `
    --set dataStorage.enabled=true `
    --set image.registry=dhi.io `
    --set dataStorage.size=2Gi `
    --set metrics.enabled=true `
    --set auth.enabled=true `
    --insecure-skip-tls-verify `
    -f ./valkey-values.yaml

# Write-Host "[+] Pulling gitlab helm chart with provenance" -ForegroundColor Blue
# helm repo add gitlab https://charts.gitlab.io
# helm repo update
# helm pull gitlab/gitlab --prov
# Invoke-WebRequest -Uri "https://packages.gitlab.com/gpg.key" -OutFile gitlab-gpg.key
# New-Item -ItemType Directory -Force -Path "$HOME\.gnupg\"
# gpg --import .\gitlab-gpg.key
# gpg --output $HOME\.gnupg\gitlab.pubring.gpg --export "support@gitlab.com"

# Get-ChildItem -Filter "gitlab-*.tgz" | ForEach-Object { helm verify --keyring "$HOME\.gnupg\gitlab.pubring.gpg" $_.FullName }

# if (-not (Test-Path -Path "./cosign.key") -and -not (Test-Path -Path "./cosign.pub")) {
#     $env:COSIGN_PASSWORD="1234"
#     $env:COSIGN_YES="true"
#     Write-Host "[+] Generating cosign key-pair for signing artifacts." -ForegroundColor Blue
#     cosign generate-key-pair
# }

# Write-Host "[+] Creating root CA for Policy Controller - NOTE: requires approval, click 'Yes' on prompt if it pops up" -ForegroundColor Blue
# mkcert -install
# New-Item -ItemType Directory -Force -Path ".\certs" | Out-Null
# $env:CAROOT="$($pwd.Path)\certs"
# mkcert.exe -cert-file="$env:CAROOT\tls.crt" -key-file="$env:CAROOT\tls.key" host.minikube.internal 127.0.0.1
# $bytes = [System.IO.File]::ReadAllBytes("$env:CAROOT\rootCA.pem")
# $b64String = [System.Convert]::ToBase64String($bytes)

# Write-Host "[+] Pre-reqs complete! Setting up Kyverno inside Kubernetes to enforce signed containers." -ForegroundColor Blue
# try {
#     #Write-Host "  - setting up cosign namespace..." -ForegroundColor Green
#     #kubectl create namespace cosign-system
#     kubectl create namespace kyverno
    
#     #Write-Host "  - Adding cosign key to kubernetes" -ForegroundColor Green
#     #kubectl create secret generic upstream-public-key --namespace cosign-system --from-file=cosign.pub=cosign.pub

#     #Write-Host "  - adding cosign repo to helm..." -ForegroundColor Green
#     #helm repo add sigstore https://sigstore.github.io/helm-charts
#     #helm repo update
#     Write-Host "  - adding Kyverno repo to helm..." -ForegroundColor Green
#     helm repo add kyverno https://kyverno.github.io/kyverno/
#     helm repo update

#     #Write-Host "  - installing policy controller..." -ForegroundColor Green
#     #helm install policy-controller -n cosign-system sigstore/policy-controller --devel

    

#     #Write-Host "  - awaiting cluster for readiness..." -ForegroundColor Green
#     #kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-webhook;
#     #kubectl -n cosign-system wait --for=condition=Available deployment/policy-controller-policy-webhook;

#     Write-Host "  - enforcing compliance in cluster" -ForegroundColor Green
#     kubectl label namespace default policy.sigstore.dev/include=true
# } catch {
#     Write-Error "Sigstore setup failed. Check error and see if prerequisites exist. Removing environment"
#     minikube delete    
#     exit 1
# }

# Write-Host "[+] Starting minikube tunnel for ingress"
# Start-Job -ScriptBlock { minikube tunnel } -Name "TunnelJob"
