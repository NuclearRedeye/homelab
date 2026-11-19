# Backup requirements

How the persistent data of services defined and managed in this repo is backed up and proven restorable, wherever they run. Anything that can be rebuilt from this repo is out of scope.

## BAK-001 Back up by default
The backup system shall back up the persistent data of every service defined in this repo, unless the service opts out with a reason.
- Verify: a new service with no backup config gets backed up, on a host or in the cluster; one that opts out without a reason fails the repo checks.
- Status: proposed

## BAK-002 Copies
The backup system shall keep a copy of each backup on the local NAS and with one or more cloud providers.
- Verify: list a service's backups at every target.
- Status: proposed

## BAK-003 Data loss limit
The backup system shall back up each service's data at least every 24 hours, or on the service's own schedule where it sets a tighter one.
- Verify: the newest backup of every service at each target is within its schedule.
- Status: proposed

## BAK-004 Retention
The backup system shall keep 7 daily, 4 weekly and 6 monthly backups of each service at each target.
- Verify: after pruning, list a service's backups and count by age.
- Status: proposed

## BAK-005 Incremental backups
The backup system shall store only data that changed since the previous backup.
- Verify: back up unchanged data twice; the second run adds almost nothing to the target.
- Status: proposed

## BAK-006 Encrypted backups
The backup system shall encrypt backups before they leave the system being backed up.
- Verify: files read straight from a target contain no plaintext from a known test file.
- Status: proposed

## BAK-007 Append-only
Each target shall only allow backups to be added, with stored backups removed only by retention (BAK-004).
- Verify: using the credentials that write backups, try to change and delete a backup at each target; both fail.
- Status: proposed

## BAK-008 Restore from nothing
Everything needed to restore a backup shall be recoverable without the system that made it.
- Verify: from an unrelated host, restore a backup.
- Status: proposed

## BAK-009 Restore time
The restore process for a service to a chosen backup shall take no longer than 4 hours.
- Verify: time a restore to a backup older than the latest by following the runbook.
- Status: proposed

## BAK-010 Verified backups
The backup system shall verify each service's latest backup weekly, or on the service's own schedule, by restoring it and passing a smoke test against a copy of the service.
- Verify: every service has a passing result from the last 7 days; verifying a backup of empty data fails.
- Status: proposed

## BAK-011 Status
The backup system shall report the time and result of each backup and verification.
- Verify: the status shows each service's last backup and last verification.
- Status: proposed
