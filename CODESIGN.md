# Code Signing Setup — AltOS Installer

Code signing removes the "Unknown publisher" warning when users run the Windows installer. It is not strictly required for the app to work, but it significantly improves conversion.

## Option 1: Azure Trusted Signing (Recommended)

Microsoft's modern, cloud-based signing service. Cheaper than traditional certificates and easier to automate.

1. Create an Azure account.
2. Set up a **Trusted Signing Account** and a **certificate profile**.
3. Create an app registration and note:
   - Tenant ID
   - Client ID
   - Client Secret
   - Code Signing Account Name
   - Certificate Profile Name
4. Add these as GitHub secrets:
   - `AZURE_TENANT_ID`
   - `AZURE_CLIENT_ID`
   - `AZURE_CLIENT_SECRET`
   - `AZURE_CODE_SIGNING_NAME`
   - `AZURE_CODE_SIGNING_ACCOUNT`
   - `AZURE_CODE_SIGNING_PROFILE`
5. Uncomment the corresponding env variables in `.github/workflows/release.yml`.

## Option 2: Standard Code Signing Certificate

Purchase a certificate from a provider like DigiCert, Sectigo, or SSL.com.

1. Export the certificate as a `.pfx` file.
2. Base64-encode it and store it as a GitHub secret.
3. Update `.github/workflows/release.yml` to sign the `.exe` with `signtool` before the Tauri bundle step.

## Tauri Updater Signing

To enable auto-updates, generate an updater key pair:

```bash
npx @tauri-apps/cli signer generate
```

Store the private key and password as GitHub secrets:

- `TAURI_SIGNING_PRIVATE_KEY`
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD`

Uncomment them in `.github/workflows/release.yml`.

## Without Signing

The installer will still work. Windows Defender SmartScreen may show a warning. Users can click **More info → Run anyway**.
