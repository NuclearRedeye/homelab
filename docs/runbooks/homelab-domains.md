# Homelab Domains

Finding, adding and removing the domains the cluster serves. Each domain has a codename, a Transformers planet, so the real names stay out of this public repo. The mapping lives only in `kubernetes/settings/app/settings.sops.yaml`.

## When to Use

- You need to know which real domain a codename (`cybertron`, `junkion`, `quintessa`) stands for, or the reverse.
- You're adding a domain to, or dropping one from, the Gateway.

## When Not to Use

- A certificate won't issue or renew for a domain that's already set up. That's a cert-manager problem; start with `kubectl describe certificate -n traefik <codename>`.
- You're adding a hostname one level under an existing domain, like `app.<domain>`. The wildcard certificate already covers it; only an `HTTPRoute` is needed. A deeper name like `app.team.<domain>` isn't covered: the listener still accepts it, but clients get a certificate error, so it needs its own `Certificate`.

## Before You Start

- Run everything from the dev shell, with the admin age key. Every `kubernetes/` secret is encrypted to it.
- Never write a real domain into the repo, an issue or a PR. Only the codename.

## Steps

### Look Up a Codename

Each domain is a `<CODENAME>_DOMAIN` key in the cluster settings. The key names are readable without decrypting, but the values aren't.

```sh
sops decrypt kubernetes/settings/app/settings.sops.yaml | grep _DOMAIN
```

Each line reads `CYBERTRON_DOMAIN: <real domain>`. The codename is used, lowercase, as the `Certificate` name, its `<codename>-tls` Secret and the `https-<codename>` listener in `kubernetes/apps/traefik/config/`.

### Add a Domain

1. Choose a Transformers planet not yet in use as the codename.
2. Add the domain's zone to the Cloudflare API token's Zone Resources. Otherwise DNS-01 fails for it.
3. Add the setting, with the bare domain (no `*.` or trailing dot):

   ```sh
   sops set kubernetes/settings/app/settings.sops.yaml '["stringData"]["<CODENAME>_DOMAIN"]' '"<domain>"'
   ```

4. Add a placeholder to `kubernetes/validate.sh`, e.g. `export <CODENAME>_DOMAIN=<codename>.example`. Its `--strict` check fails without one.
5. In `kubernetes/apps/traefik/config/`, copy an existing domain's `Certificate` in `certificates.yaml` and its `https-<codename>` listener in `gateway.yaml`, then rename them.
6. Run `kubernetes/validate.sh`, then open a PR.

### Remove a Domain

1. Find its codename using Look Up a Codename.
2. Find every `HTTPRoute` that uses the domain, then move each one to another domain or remove it. Otherwise its app goes offline when the listener does.

   ```sh
   grep -rln -e '<CODENAME>_DOMAIN' -e 'https-<codename>' kubernetes/apps
   ```

   Good output lists only `kubernetes/apps/traefik/config/` files, which the next steps edit.
3. Remove its `Certificate` from `certificates.yaml` and its listener from `gateway.yaml`, then its placeholder from `validate.sh`.
4. Remove the setting:

   ```sh
   sops unset kubernetes/settings/app/settings.sops.yaml '["stringData"]["<CODENAME>_DOMAIN"]'
   ```

5. Run `kubernetes/validate.sh`, then open a PR, and merge it.
6. Delete the leftover certificate Secret. cert-manager doesn't delete it when Flux prunes the `Certificate`:

   ```sh
   kubectl delete secret -n traefik <codename>-tls
   ```

7. Remove the domain's `address=` entry from the router's dnsmasq, and its zone from the Cloudflare API token.

## Verify

After a Flux reconcile:

```sh
kubectl get certificate -n traefik
kubectl get gateway -n traefik traefik -o jsonpath='{range .status.listeners[*]}{.name}{"\t"}{.conditions[?(@.type=="Programmed")].status}{"\n"}{end}'
```

- Good: one `Certificate` per codename, each `READY True`, and one `https-<codename>` listener per codename, each `True`. A removed codename appears in neither.
- A new `Certificate` stays `False`: issuance takes a few minutes. If it's still `False` after 10, `kubectl describe certificate -n traefik <codename>` names the failing step. A Cloudflare permission error means step 2 of Add a Domain was missed.
- A listener is `False`: its `<codename>-tls` Secret doesn't exist yet. It turns `True` once the `Certificate` is ready.
