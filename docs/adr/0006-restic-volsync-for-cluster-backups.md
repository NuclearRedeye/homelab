---
status: accepted
---

# Restic with VolSync over SFTP for cluster backups

Cluster apps need their data backed up to the NAS and a cloud target, and restored to a chosen backup, to meet the [backup requirements](../requirements/backups.md). We chose restic, run by VolSync from one shared Kustomize component, writing over SFTP through restic's rclone backend, with restores run by a script. restic is the only engine with both a NixOS module and a VolSync mover, so hosts and the cluster back up the same way, and SFTP needs nothing on the NAS beyond a user.

## Considered Options

- **Kopia:** rejected, as VolSync has no Kopia mover and nixpkgs has no Kopia module.
- **Mounting the NAS (NFS or SMB):** rejected, as NAS mounts have hung host boots after power cuts, and NFS trusts client IPs.
- **One backup to both targets (rclone union):** rejected, as a failure at one target fails both, and damage is copied to both.
- **Snapshot copy method for backups:** rejected, as LINSTOR clones on the thin pool already share blocks and it would still make a temporary volume.
- **Restore on creation (VolSync's volume populator):** rejected, as it needs CSI snapshots and a snapshot per app. Its copy is only as fresh as its last restore, so deleting a PVC can bring back old or empty data, and starting an app fresh means emptying its repositories too.
- **Per-app backup times, or a job queue:** deferred until the NAS is seen to struggle; the queue is spiked in #180.

## Consequences

- Each backed-up volume has two ReplicationSources, one per target, each with its own repository. Each app has one restic password per target, shared by its volumes.
- Restoring is always a manual step, including after a cluster rebuild: the script scales the app down, restores the chosen backup into its PVC and scales it back up.
- A new ReplicationSource backs up straight away, so a rebuilt cluster would back up every app's empty volume. Backups are paused cluster-wide by a setting until the restores are done.
- Deleting an app's PVC starts it fresh, and its old backups age out through retention. Removing an app leaves its repositories at each target until they are deleted by hand.
- Retention only runs during a backup, and VolSync can't protect tagged backups, so suspended apps keep all their backups and archived backups go in a separate repository.
- Every app backs up at the same time, to the NAS at 01:00 and the cloud at 02:00, so the NAS's single CPU core is shared between them.
- Every backed-up namespace holds the NAS's SSH key, so one compromised app could delete all NAS backups. The cloud target's recoverable deletes (BAK-007) are the safety net.
- Backups copy volumes while apps run, so they are only crash-consistent.
- VolSync doesn't support SFTP natively; we rely on it passing `RCLONE_*` settings to the rclone bundled in its mover image.
