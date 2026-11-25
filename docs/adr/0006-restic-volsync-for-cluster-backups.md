---
status: accepted
---

# Restic with VolSync over SFTP for cluster backups

Cluster apps need their data backed up to the NAS and a cloud target, and restored to a chosen backup, to meet the [backup requirements](../requirements/backups.md). We chose restic, run by VolSync from one shared Kustomize component, writing over SFTP through restic's rclone backend to the NAS and a Hetzner Storage Box, with restores, manual backups and archives run by scripts. restic is the only engine with a VolSync mover, and hosts can use it too (#169); SFTP needs nothing on either target beyond a user.

## Considered Options

- **Kopia:** rejected, as VolSync has no Kopia mover.
- **Mounting the NAS (NFS or SMB):** rejected, as NAS mounts have hung host boots after power cuts, and NFS trusts client IPs.
- **One backup to both targets (rclone union):** rejected, as a failure at one target fails both, and damage is copied to both.
- **Snapshot copy method for backups:** rejected, as LINSTOR clones on the thin pool already share blocks and it would still make a temporary volume.
- **Restore on creation (VolSync's volume populator):** rejected, as it needs CSI snapshots and a snapshot per app, and deleting a PVC can bring back old or empty data.
- **Restores declared in Git, or a paused ReplicationDestination per volume:** rejected, as a rebuild would replay old restores, and a paused one sits aimed at live data.
- **A separate archive repository:** rejected, as it needs `restic copy` jobs and more secrets.
- **Hetzner Object Storage with object lock:** kept as the fallback, as the Storage Box's snapshots already make deletes recoverable (BAK-007).
- **Per-app backup times, or a job queue:** deferred until the NAS is seen to struggle; the queue is spiked in #180.

## Consequences

- Restoring is always manual, including after a rebuild. Backups are paused cluster-wide by a flag until the restores are done, as a new ReplicationSource backs up straight away.
- Archives stay in the same repository, rehosted to `archive`. They survive retention only because VolSync's forget prunes host `volsync` alone, which is VolSync's behaviour, not a promise.
- Suspending an app pauses its backups too, so it keeps all of them until resumed.
- Every PVC must say whether it's backed up, enforced by an admission policy (#165).
- Every backed-up namespace holds the NAS's and the Storage Box sub-account's SSH keys, so one compromised app could delete every backup at both. The Storage Box's weekly snapshots, out of the sub-account's reach, are the safety net, so up to a week of cloud backups can be lost.
- Every app backs up at the same time, to the NAS at 01:00 and the cloud at 02:00, so the NAS's single CPU core is shared between them.
- Backups copy volumes while apps run, so they are only crash-consistent.
- VolSync doesn't support SFTP natively; we rely on it passing `RCLONE_*` settings to the rclone bundled in its mover image.
