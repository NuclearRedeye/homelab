# Service Recovery

Restoring a service's volume from a backup, replacing everything on it. The end state is the service running on the restored data, with its backups carrying on.

## When to Use

- A service's data has been deleted, damaged or lost, e.g. after a bad upgrade.
- You want to roll a service back to an earlier backup, or to a named archive.
- A service's volume was deleted while it was suspended, and you want to bring it back.

## When Not to Use

- You want to take or list backups. Use the [service backups](service-backups.md) runbook instead.
- The whole cluster has been lost. Use the cluster disaster recovery runbook (#222), which links back here for each service.

## Before You Start

- Activate the dev shell. `nix develop`.
- Ensure the cluster is up. `kubectl get nodes` should list every node `Ready`.
- `<service>` is the service's Flux Kustomization's `APP`, which is also its namespace.
- The script takes `--volume` only if a service has more than one persistent, backed-up volume.
- The service is down for the whole restore.

## Steps

### Choose a Backup

1. List the backups and archives at every target using...

   ```sh
   scripts/restore.sh --service <service> --list
   ```

   Pick the `TIME` of the backup to restore, or an archive's `NAME`. Restore from the NAS if it has the backup you want, as it's faster; use `cloud` if it doesn't, or the NAS is down.

2. Optional: if you might want the service's current data back later, archive it first using the [service backups](service-backups.md#archive-a-backup) runbook. The restore is backed up as soon as it finishes, replacing that day's earlier backup at each target.

### Restore

This replaces everything on the volume, and stops the service until it finishes.

1. Restore using one of...

   ```sh
   scripts/restore.sh --service <service>                               # latest backup at the NAS
   scripts/restore.sh --service <service> --restore-point <time>        # newest backup at or before <time>
   scripts/restore.sh --service <service> --archive <name>              # a named archive
   ```

   Add `--source cloud` to restore from the cloud instead of the NAS. It shows what it will restore, then asks.

2. It should end with the mover's log and `Resuming <kustomization>`. Flux then starts the service again, and recreates its backups so the next one is of the restored data.

If it fails, it stops with the service still down and its Flux Kustomization suspended, and prints the mover's log. Fix the cause and run it again, or bring the service back unrestored using `flux resume kustomization <kustomization>`.

## Verify

- The service is running, using `kubectl -n <service> get pods`, and its data is as expected.
- `scripts/restore.sh --service <service> --list` shows a new backup at each target from just after the restore, unless the service is suspended.
