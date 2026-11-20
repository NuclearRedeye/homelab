# Backup requirements

How the persistent data of services defined and managed in this repo is backed up and proven restorable, wherever they run. Hosts and the cluster are rebuilt from this repo, so only service data is backed up. Anything else needed to recover is kept outside the system and documented.

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
The backup system shall keep 7 daily, 4 weekly and 6 monthly backups of each service at each target, except backups of a suspended service and archived backups, which are kept until deleted.
- Verify: after pruning, list a service's backups and count by age; a suspended service and an archived backup lose none.
- Status: proposed

## BAK-005 Incremental backups
The backup system shall store only data not already held at the target, so unchanged files and repeated content are stored once.
- Verify: back up unchanged data twice, then a copy of an existing file; neither run adds more than a little to the target.
- Status: proposed

## BAK-006 Encrypted backups
The backup system shall encrypt backups before they leave the system being backed up.
- Verify: files read straight from a target contain no plaintext from a known test file.
- Status: proposed

## BAK-007 Recoverable deletes
Each cloud target shall keep backups older than a week recoverable for at least 30 days after they are changed or deleted, including by the credentials that write backups.
- Verify: using the credentials that write backups, delete a backup older than a week at each cloud target, then recover it.
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
