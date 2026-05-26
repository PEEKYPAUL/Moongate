# generate-master-key.ps1
#
# Generates a 32-byte cryptographically-random key, base64-encoded.
# Use this as MOONGATE_TUNNEL_URL_KEY in Supabase Edge Functions.
#
# Run from PowerShell:
#   .\supabase\scripts\generate-master-key.ps1
#
# The key is printed to the console only. It is NOT saved to disk anywhere.
# Copy it into your password manager AND into the Supabase dashboard
# (Edge Functions -> Manage secrets -> MOONGATE_TUNNEL_URL_KEY).
#
# WARNING: rotating this key after data is encrypted will make all existing
# tunnel_url_enc rows unreadable. Treat it as permanent.

$ErrorActionPreference = 'Stop'

$bytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try {
    $rng.GetBytes($bytes)
} finally {
    $rng.Dispose()
}

$key = [Convert]::ToBase64String($bytes)

Write-Host ""
Write-Host "MOONGATE_TUNNEL_URL_KEY (base64, 32 bytes):" -ForegroundColor Cyan
Write-Host ""
Write-Host "    $key" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Green
Write-Host "  1. Copy the value above into your password manager."
Write-Host "  2. Open Supabase dashboard -> Edge Functions -> Manage secrets."
Write-Host "  3. Add a secret named MOONGATE_TUNNEL_URL_KEY with the value above."
Write-Host "  4. Save."
Write-Host ""
Write-Host "Do NOT commit this key anywhere. Do NOT paste it into Slack/email/issues." -ForegroundColor Red
Write-Host ""
