<#
.SYNOPSIS
    Smoke-test Keycloak installation behind Apache proxy.

.DESCRIPTION
    - Prompts for Keycloak host, realm, admin username & password (with defaults).
    - Tests:
        1. OpenID discovery endpoint
        2. Token endpoint (admin-cli password grant)
        3. Admin REST API (list realms)
#>

param()

function Prompt-Default($message, $default) {
    $input = Read-Host "$message [$default]"
    if ([string]::IsNullOrWhiteSpace($input)) {
        return $default
    }
    return $input
}

# === Prompt user with defaults ===
$KC_HOST   = Prompt-Default "Keycloak Host" "https://auth.sivargpt.com"
$KC_REALM  = Prompt-Default "Realm" "master"
$KC_USER   = Prompt-Default "Admin Username" "keycloakadmin"
$KC_PASS   = Read-Host -Prompt "Admin Password [default: 1234567890]" -AsSecureString

# Convert SecureString to plain text (safe for testing only)
$BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($KC_PASS)
$KC_PASS_PLAIN = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
if (-not $KC_PASS_PLAIN) { $KC_PASS_PLAIN = "1234567890" }

Write-Host "`n[*] Testing Keycloak at $KC_HOST (realm: $KC_REALM)`n"

# === 1) Test discovery ===
$discoveryUrl = "$KC_HOST/realms/$KC_REALM/.well-known/openid-configuration"
try {
    $discovery = Invoke-RestMethod -Uri $discoveryUrl -Method GET -UseBasicParsing
    Write-Host "[OK] Discovery endpoint reachable"
} catch {
    Write-Error "[FAIL] Discovery endpoint: $discoveryUrl"
    exit 1
}

# === 2) Request admin token ===
$tokenUrl = "$KC_HOST/realms/master/protocol/openid-connect/token"
try {
    $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method POST -UseBasicParsing `
        -Body @{
            client_id  = "admin-cli"
            grant_type = "password"
            username   = $KC_USER
            password   = $KC_PASS_PLAIN
        }

    $accessToken = $tokenResponse.access_token
    if ($accessToken) {
        Write-Host "[OK] Retrieved admin access token"
    } else {
        Write-Error "[FAIL] Could not retrieve admin token"
        exit 1
    }
} catch {
    Write-Error "[FAIL] Token endpoint: $tokenUrl"
    exit 1
}

# === 3) Call Admin REST API ===
$realmsUrl = "$KC_HOST/admin/realms"
try {
    $headers = @{ Authorization = "Bearer $accessToken" }
    $realms = Invoke-RestMethod -Uri $realmsUrl -Headers $headers -UseBasicParsing
    $realmNames = $realms | ForEach-Object { $_.realm }
    Write-Host "[OK] Admin REST API reachable. Realms found:" ($realmNames -join ", ")
} catch {
    Write-Error "[FAIL] Admin REST API: $realmsUrl"
    exit 1
}

Write-Host "`nAll tests passed ✔"
