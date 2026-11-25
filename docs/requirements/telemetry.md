# Telemetry requirements

How metrics and logs from every system on the internal network, whether defined in this repo or not, are collected, kept and turned into alerts. Traces are out of scope for now.

## TEL-001 Metrics and logs
The telemetry system shall collect both metrics and logs from each source that provides them.
- Verify: every source that provides metrics and logs shows both from the last 5 minutes.
- Status: proposed

## TEL-002 Open standards
The telemetry system shall receive telemetry only through open standards.
- Verify: list each source and the standard it uses; none needs a vendor-specific agent.
- Status: proposed

## TEL-003 Host resources and health
The telemetry system shall collect each host's resource use and hardware health.
- Verify: every host shows its resource use, such as CPU and memory, and hardware health, such as drive health.
- Status: proposed

## TEL-004 Service up or down
When a service stops, the telemetry system shall show it as down within 5 minutes.
- Verify: stop a service and time until it shows as down.
- Status: proposed

## TEL-005 Service metrics
Where a service exposes its own metrics, the telemetry system shall collect them.
- Verify: every service that exposes metrics shows them.
- Status: proposed

## TEL-006 Collect by pulling
Where a source can't reach the telemetry system, the telemetry system shall fetch telemetry from that source.
- Verify: collect from a source with no route or name lookup to the telemetry system.
- Status: proposed

## TEL-007 Every host and device
The telemetry system shall collect from every host on the internal network, and every device there that supports an open standard (TEL-002).
- Verify: every host and eligible device on the network shows telemetry from the last 5 minutes.
- Status: proposed

## TEL-008 Services unless opted out
The telemetry system shall collect from every service defined in this repo, unless the service explicitly opts out.
- Verify: a new service with no telemetry config is rejected, on a host or in the cluster; one that opts out is accepted.
- Status: proposed

## TEL-009 Raise alerts
When a configured condition on metrics or logs is met, the telemetry system shall raise an alert.
- Verify: configure a disk-usage threshold; filling a throwaway disk past it raises an alert.
- Status: proposed

## TEL-010 Clear alerts
When the condition behind an alert ends, the telemetry system shall clear the alert.
- Verify: after TEL-009's test, freeing the space clears the alert.
- Status: proposed

## TEL-011 Alert delivery
When an alert is raised, the telemetry system shall send it through each configured channel, which include at least email and a push notification to a phone.
- Verify: a test alert arrives by email and on a phone.
- Status: proposed

## TEL-012 Outside watcher
If nothing is heard from the telemetry system for 15 minutes, then a system outside the internal network should alert through the TEL-011 channels.
- Verify: stop the telemetry system, or cut the internet link, and an alert arrives within 15 minutes.
- Status: proposed

## TEL-013 Retention
The telemetry system shall keep metrics for at least 90 days and logs for at least 30 days.
- Verify: query a metric from 90 days ago and a log line from 30 days ago.
- Status: proposed

## TEL-014 Dashboards
The telemetry system shall provide one place to browse metrics and search logs.
- Verify: browse a host's metrics and search its logs there.
- Status: proposed

## TEL-015 Independent alert delivery
While a service not needed to evaluate or send alerts is down, such as the dashboards, the telemetry system shall deliver alerts.
- Verify: stop the dashboards; a test alert still arrives.
- Status: proposed

## TEL-016 Alerts defined in the repo
The telemetry system shall deploy its alert conditions and channels from definitions in this repo.
- Verify: rebuild the telemetry system from the repo, and its conditions and channels are back without manual steps.
- Status: proposed

## TEL-017 Encrypted in transit
Where a source supports it, the telemetry system should receive that source's telemetry encrypted in transit.
- Verify: list each source and whether its telemetry is encrypted; every unencrypted source has a reason.
- Status: proposed
