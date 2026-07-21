# Dayline website

The website and anonymous feedback relay run on the `dayline-website`
Cloudflare Worker.

## Rotating the feedback bot key

GitHub downloads GitHub App private keys as PKCS#1 PEM files. The Worker imports
the key through Web Crypto, so convert it to an unencrypted PKCS#8 PEM before
uploading it:

```bash
openssl pkcs8 -topk8 -nocrypt -in github-app.pem -out github-app-pkcs8.pem
bunx wrangler secret put GITHUB_PRIVATE_KEY < github-app-pkcs8.pem
```

Delete both local key files after the secret upload succeeds. Never commit them.
