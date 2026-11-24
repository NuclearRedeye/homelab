# Service Backups

Listing a service's backups, taking one now, and keeping one as a named archive until it's deleted.

## When to Use

- You want to see what backups a service has.
- You need to take a backup now, e.g. before some maintenance or an upgrade.
- You want to create a named backup that will persist until it's manually deleted.
- You want to delete a named backup.

## When Not to Use

- You need to take a daily, weekly or monthly backup. These run automatically every night, to the NAS at 01:00 UTC and the cloud at 02:00 UTC.
- You want to restore a backup. Use the [service recovery](service-recovery.md) runbook instead.

## Before You Start

- Activate the dev shell. `nix develop`.
- Ensure the cluster is up. `kubectl get nodes` should list every node `Ready`.
- `<service>` is the service's Flux Kustomization's `APP`, which is also its namespace.
- The scripts take `--volume` only if a service has more than one persistent, backed-up volume.

## Steps

### List a Service's Backups

1. List the backups and archives at every target using...

   ```sh
   scripts/backup.sh --service <service> --list
   ```

   It prints one table, newest first, with each backup's time, target, snapshot ID, size and, for an archive, its name. Expect a backup from the last day at each target, and up to 17 per target besides archives.

2. Optional: check each target's repository is sound using...

   ```sh
   scripts/backup.sh --service <service> --check
   ```

   It should print `no errors were found` for each target. Avoid 01:00–03:00 UTC, as it delays a nightly backup that starts meanwhile.

### Take a Backup Now

A manual backup replaces that day's nightly one at each target. If you may need the day's earlier state, archive it instead.

1. Back up to every target using...

   ```sh
   scripts/backup.sh --service <service>
   ```

   Add `--target nas` or `--target cloud` for one. Add `--stop` to stop the service during the backup, for a consistent copy; it asks first, and starts the service again afterwards.

2. It should print `Backed up at <time>` for each target.

### Archive a Backup

An archive is a backup kept until you delete it, under a name of lowercase letters, digits and hyphens, e.g. `before-upgrade`.

1. Take and archive a backup using...

   ```sh
   scripts/backup.sh --service <service> --stop --archive <name>
   ```

   It should print `Archived as <name>` for each target. A name already used at any target makes it stop before backing up.

2. Check it's listed with its name using `scripts/backup.sh --service <service> --list`.

### Delete an Archive

This can't be undone at the NAS.

1. Delete it from every target using...

   ```sh
   scripts/archive.sh --service <service> --delete <name>
   ```

   It shows the snapshots that will go, then asks. Add `--target` for one target. It should print `Deleted <name> at <target>` for each.

2. Check it's gone using `scripts/backup.sh --service <service> --list`.

## Verify

- `scripts/backup.sh --service <service> --list` shows a backup from the last day at every target, and any archives by name.
- If a command fails, it prints why. A `repository is already locked` error usually means a nightly backup is running; try again once it finishes.
