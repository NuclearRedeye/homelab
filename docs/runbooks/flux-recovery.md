# Flux Recovery

Reinstalling Flux from this repo when it's broken or gone, including when its age key is lost. The end state is Flux reconciling `main` with every app back and every secret decrypting.

## When to Use

- Flux is missing, e.g. after rebuilding the cluster using the [k3s etcd recovery](k3s-etcd-recovery.md) runbook.
- The `flux-system` namespace, its controllers or the `sops-age` Secret are lost or damaged beyond a `flux reconcile`.
- The Flux age key is lost. No copy is kept, so recovery always makes a new one.

## When Not to Use

- One app is failing. Fix it in Git, or `flux suspend ks <app>` while you do.
- The cluster itself is down. Use the [k3s etcd recovery](k3s-etcd-recovery.md) runbook first, then come back.
- The Flux age key has leaked rather than been lost. Follow this runbook, then Rotate a Leaked Key.

## Before You Start

- Run everything from the dev shell, against a cluster that's up. `kubectl get nodes` should list every node `Ready`.
- Have the admin age key, which is a recipient on every `kubernetes/` secret. `sops -d kubernetes/settings/app/settings.sops.yaml` should print the plaintext.
- Create a short-lived PAT for bootstrap at [New fine-grained token](https://github.com/settings/personal-access-tokens/new)...

  - **Token name:** `flux-bootstrap`.
  - **Expiration:** 1 day, using Custom if it isn't offered.
  - **Resource owner:** `NuclearRedeye`.
  - **Repository access:** Only select repositories, then `homelab`.
  - **Repository permissions:** Contents read and write, so bootstrap can push if anything differs, and Administration read and write, so it can replace the deploy key. Metadata read-only is added automatically.

  Generate it and copy the token. Don't export it as `GITHUB_TOKEN`: when that's unset, bootstrap prompts for the token, which keeps it out of your shell history.

## Steps

### Tear Down What's Left

Skip this if `kubectl get ns flux-system` says `NotFound`.

**Never `kubectl delete ns flux-system`, or delete a Kustomization, while the controllers are running.** Their finalizers prune every app Flux manages. `flux uninstall` removes the finalizers first, and the guardrail policy refuses it until both objects are annotated.

1. Allow the teardown using...

   ```sh
   kubectl annotate ns flux-system homelab/allow-delete=true
   kubectl annotate ks flux-system -n flux-system homelab/allow-delete=true
   ```

2. Uninstall Flux, answering `y` to the prompt...

   ```sh
   flux uninstall
   kubectl wait --for=delete ns/flux-system --timeout=3m
   ```

   It should end with `✔ uninstall finished` and `condition met`. Apps and the guardrail policy keep running, unmanaged, until bootstrap adopts them again.

### Create a New Key

1. Create the namespace, then pipe a new key straight into the cluster so the private half never touches disk...

   ```sh
   kubectl create ns flux-system
   age-keygen 2>/dev/tty \
     | kubectl create secret generic sops-age -n flux-system --from-file=age.agekey=/dev/stdin
   ```

2. Note the printed `Public key: age1…`. You need it in the next phase.

The new namespace isn't annotated, so the guardrail protects it straight away. `kubectl delete ns flux-system --dry-run=server` should be denied.

### Re-key the Secrets

1. Replace `&flux` in `.sops.yaml` with the new public key.
2. Re-key every cluster secret using...

   ```sh
   for f in $(git ls-files 'kubernetes/*.sops.yaml'); do sops updatekeys -y "$f"; done
   ```

   Each file should report `synced with new keys`, adding the new key and removing the old one.
3. Check each file still decrypts using `sops -d <file>`.
4. Run `kubernetes/validate.sh`, then PR and merge.

### Bootstrap

1. Bootstrap, pasting the PAT when prompted...

   ```sh
   flux bootstrap github \
     --owner=NuclearRedeye --repository=homelab --personal \
     --branch=main --path=kubernetes
   ```

   It should report `component manifests are up to date` and `sync manifests are up to date`, meaning it commits nothing. It replaces the repo's deploy key rather than adding another.
2. Revoke the PAT under [Fine-grained tokens](https://github.com/settings/personal-access-tokens) by deleting `flux-bootstrap`.

### Rotate a Leaked Key

`updatekeys` only re-wraps each file's data key, so a leaked key plus the old ciphertext in Git history still reveals every value. After the phases above...

1. Give each file a new data key using `sops rotate -i <file>`, then PR and merge.
2. Change every secret value at its source, since the old values stay readable from history.

## Verify

- `git log origin/main -1 --oneline` is still your re-key merge. If bootstrap committed, compare its commit with `kubernetes/flux-system/` to see what differed.
- `flux get ks -A` shows every Kustomization `Ready`. If one shows `decryption failed`, check `.sops.yaml` and `sops-age` hold the same key.
- Secrets decrypt in the cluster: `kubectl get secret -n <namespace> <name> -o jsonpath='{.data.<key>}' | base64 -d` prints the plaintext, which `sops -d` on the file in Git shows.
- `gh api repos/NuclearRedeye/homelab/keys --jq '.[].title'` lists exactly one deploy key. Delete any other in the repo's settings.

## Timings

From the exercise in #69, with only a smoke-test app and the guardrail installed:

| Phase | Took |
|---|---|
| Tear Down What's Left | 27s |
| Create a New Key | 23s |
| Re-key the Secrets | a few minutes, mostly PR review |
| Bootstrap | 35s |
