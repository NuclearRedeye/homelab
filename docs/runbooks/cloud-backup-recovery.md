# Cloud Backup Recovery

Bringing back a service's cloud backups from a Storage Box snapshot, after they've been deleted or damaged, then restoring the service from them if its data is lost too. The end state is the cloud repository as it was at that snapshot, passing `backup.sh --check`.

## When to Use

- A service's cloud backups have been deleted, e.g. by leaked or misused backup credentials, or by mistake.
- `scripts/backup.sh --service <service> --check --target cloud` reports errors.
- The backup you need is missing at both targets, and was at the cloud more than a week ago.

## When Not to Use

- The NAS still has the backup you need. Restore from it using the [service recovery](service-recovery.md) runbook instead.

## Before You Start

- Activate the dev shell. `nix develop`.
- Choose the snapshot: the newest one from before the damage. The Storage Box takes one every Sunday at 04:00 UTC and keeps 10, so any cloud backups since then are lost; the NAS may still have them.
- Choose how to bring it back:
  - **One or a few services:** copy each repository back over SSH. You need the Storage Box main account's SSH key, and its host and user from the Hetzner Console. The cluster's own credentials can't reach snapshots, by design.
  - **Every service:** restore the whole snapshot in the Hetzner Console.
- Avoid 02:00–03:00 UTC, when the nightly cloud backup runs.

## Steps

### Copy One Service's Backups Back

This opens the main account, which can delete everything, to SSH from anywhere. Close it again as soon as you're done.

1. In the Hetzner Console, open the Storage Box's settings, and turn on SSH support, external reachability and ZFS snapshot visibility.
2. Check you can log in and see the snapshot using...

   ```sh
   ssh -p 23 <user>@<host> ls .zfs/snapshot
   ```

   It should list snapshots by time, e.g. `2026-11-23T19-53-57`.

3. Move the damaged repository aside, if there is one, using...

   ```sh
   ssh -p 23 <user>@<host> mv k3s/<service>/<volume> k3s/<service>/<volume>.damaged
   ```

4. Copy it from the snapshot using...

   ```sh
   ssh -p 23 <user>@<host> cp -a .zfs/snapshot/<snapshot>/k3s/<service>/<volume> k3s/<service>/
   ```

   Repeat steps 3 and 4 for each service.

5. Check each repository is sound using...

   ```sh
   scripts/backup.sh --service <service> --check --target cloud
   ```

   It should print `no errors were found`. If not, copy from an older snapshot.

6. Delete each damaged copy using `ssh -p 23 <user>@<host> rm -r k3s/<service>/<volume>.damaged`.
7. In the Hetzner Console, turn off SSH support, external reachability and ZFS snapshot visibility for the main account, and check `ssh -p 23 <user>@<host>` is refused.

### Restore Every Service's Backups

This can't be undone. It rolls back everything on the Storage Box, every sub-account's folder included, and permanently deletes every snapshot newer than the one you restore. You can still restore an older one afterwards, but never a newer one.

1. In the Hetzner Console, open the Storage Box's snapshots, and restore the one you chose.
2. Check each service's repository is sound using...

   ```sh
   scripts/backup.sh --service <service> --check --target cloud
   ```

   It should print `no errors were found`. If not, restore an older snapshot.

### Restore the Service

Skip this if the service's own data is fine, and only its backups were lost.

1. Restore it from the cloud, adding `--source cloud`, using the [service recovery](service-recovery.md) runbook.

## Verify

- `scripts/restore.sh --service <service> --list --source cloud` shows the backups the snapshot held.
- The next nightly cloud backup succeeds, shown by a new backup in that list.
