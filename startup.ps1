Write-Host "[+] Checking for WSL:"

wsl --status *>&1 > $null
if ($LASTEXITCODE -eq 0) {
    Write-Host "  - WSL Installed"
} else {
    Write-Host "  - Installing WSL"
    wsl --install
}