# Service Suspension

Stopping a service and pausing its backups without losing its data, so it can be resumed later.

## When to Use

- You want to stop a service for a while, e.g. one you rarely use, but may want back.
- You want to resume a suspended service.

## When Not to Use

- You want to stop a service briefly, e.g. for maintenance. Run `flux suspend kustomization <service>`, scale its workloads to 0 with `kubectl scale`, then `flux resume kustomization <service>` when done, which starts them again.
- You want to remove a service for good. Delete its directory from `kubernetes/apps/` instead; its data and backups are kept until you delete them.

## Before You Start

- Activate the dev shell. `nix develop`.
- Ensure the cluster is up. `kubectl get nodes` should list every node `Ready`.
- `<service>` is the service's Flux Kustomization's `APP`, which is also its namespace and its directory under `kubernetes/apps/`.
- The service's workloads must set `replicas: ${REPLICAS:=1}`, e.g. `controllers.main.replicas` in its app-template values. If they don't, add it in the same change as suspending.
- Suspending keeps the service's volumes and every backup. Paused backups are never pruned, so the last nightly ones stay until you resume.

## Steps

### Suspend

1. Optional: if you might want today's data back, archive it now using the [service backups](service-backups.md#archive-a-backup) runbook. It can't archive once backups are paused.
2. In `kubernetes/apps/<service>/ks.yaml`, add these two lines to `postBuild.substitute`...

   ```yaml
   REPLICAS: "0"
   VOLSYNC_PAUSED: "true"
   ```

3. Merge the change to `main`, then apply it now using...

   ```sh
   flux reconcile kustomization <service> --with-source
   ```

### Resume

1. If the service's volume was deleted while it was suspended, restore it first, using the [service recovery](service-recovery.md) runbook. Otherwise its first backup would be of an empty volume.
2. Delete these two lines from `kubernetes/apps/<service>/ks.yaml`. Don't set them to `"1"` or `"false"`, which would stop the cluster's own `VOLSYNC_PAUSED` pausing backups during a rebuild.

   ```yaml
   REPLICAS: "0"
   VOLSYNC_PAUSED: "true"
   ```

3. Merge the change to `main`, then apply it now using...

   ```sh
   flux reconcile kustomization <service> --with-source
   ```

## Verify

- After suspending, `kubectl -n <service> get pods` lists no pods for the service, and `kubectl -n <service> get replicationsources -o custom-columns=NAME:.metadata.name,PAUSED:.spec.paused` shows each one `true`.
- After resuming, the service's pods are running and its data is as expected, and the same command shows each one `<none>`. `scripts/backup.sh --service <service> --list` shows a new backup at each target after the next nightly run.
