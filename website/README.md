# Dayline website

The website and anonymous feedback relay run on the `dayline-website`
Cloudflare Worker.

## Rotating the feedback bot key

Create a new private key in the GitHub App settings without deleting the current
key. GitHub downloads the new key as a PKCS#1 PEM file. The Worker imports the
key through Web Crypto, so convert it to an unencrypted PKCS#8 PEM and upload it:

```bash
openssl pkcs8 -topk8 -nocrypt -in github-app.pem -out github-app-pkcs8.pem
bunx wrangler secret put GITHUB_PRIVATE_KEY < github-app-pkcs8.pem
```

Submit a test feedback report and confirm the Worker creates the GitHub issue.
Only then delete the previous private key in the GitHub App settings. Delete both
local key files after the secret upload succeeds. Never commit them.
