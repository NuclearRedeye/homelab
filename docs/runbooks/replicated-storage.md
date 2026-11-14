# Replicated Storage

Inspecting and recovering volumes on the `linstor-replicated` StorageClass. Each volume is a DRBD resource with a copy on every k3s node, managed by LINSTOR through the Piraeus operator.

## When to Use

- You need to read or change files in a volume, e.g. to inspect or repair an app's data.
- A node has gone down, and pods or volumes haven't recovered by themselves.
- A replica is missing, `Outdated` or slow to resync after a node returns.

## When Not to Use

- After a drain or a clean reboot, no action is needed: pods move within about a minute and replicas resync by themselves.
- The cluster itself is down. Use the [k3s etcd recovery](k3s-etcd-recovery.md) runbook first, then come back.

## Before You Start

- Run `kubectl` from the dev shell. If the server your kubeconfig points at is down, add `--server https://<host>:6443` for one that's up.
- Have ssh and sudo on each node.
- The hosts have no DRBD tools: `drbdadm` and `drbdsetup` live in each node's satellite container. The dev shell defines two helpers: `lin <args>` runs `linstor` in the controller, and `drbd <node> <command>` runs a command in that node's satellite. Find the volume's resource name from its claim...

  ```sh
  R=$(kubectl -n <namespace> get pvc <claim> -o jsonpath='{.spec.volumeName}')
  ```

**Never mount the thin LV (`/dev/linstor_thin/pvc-…_00000`) directly.** Writes there bypass DRBD, so the other replicas never see them and the copies silently diverge. Always go through the DRBD device, and only while nothing else has it Primary.

## Steps

### Check a Volume

1. Show each replica using `lin resource list -r $R`, and its device and space using `lin resource list-volumes -r $R`.
2. Read the `State` column...

   | State | Meaning |
   |---|---|
   | `UpToDate` | A good copy. |
   | `Outdated` | Missed writes while away; resyncs on reconnect. |
   | `Inconsistent`, `SyncTarget(n%)` | Being resynced from a good copy. |
   | `Diskless` | A tiebreaker LINSTOR adds when only two copies have disks; it votes but holds no data. |
   | `Unknown` | Its node is unreachable. |

3. For more detail, including resync speed and time left, run `drbd <node> drbdsetup status $R --verbose --statistics` against a node with a good copy.

### Inspect Through a Debug Pod

Use this while the app is running, e.g. when its image has no shell. A `ReadWriteOnce` volume can be mounted by several pods, but only on one node.

1. Find the app's node using `kubectl -n <namespace> get pod <pod> -o wide`.
2. Apply a pod pinned to that node and mounting the same claim. Pick a `runAsUser` the app's files allow...

   ```yaml
   apiVersion: v1
   kind: Pod
   metadata:
     name: inspect
     namespace: <namespace>
   spec:
     nodeName: <node>
     securityContext:
       runAsNonRoot: true
       runAsUser: 1000
       seccompProfile:
         type: RuntimeDefault
     containers:
     - name: shell
       image: busybox:1.37
       command: [sleep, infinity]
       securityContext:
         allowPrivilegeEscalation: false
         capabilities:
           drop: [ALL]
       volumeMounts:
       - name: data
         mountPath: /data
     volumes:
     - name: data
       persistentVolumeClaim:
         claimName: <claim>
   ```

3. Work in it using `kubectl -n <namespace> exec -it inspect -- sh`, then delete it using `kubectl -n <namespace> delete pod inspect`.

### Break-Glass Mount on a Node

Use this when no pod can mount the volume, e.g. to repair a filesystem. The app must be stopped first.

1. Scale the app to 0 using `kubectl -n <namespace> scale deploy/<app> --replicas=0`, and wait for its pod to go.
2. Check `lin resource list -r $R` shows every replica `Unused`. **Don't continue while any is `InUse`.**
3. Pick a node with an `UpToDate` copy, and find the device in `lin resource list-volumes -r $R`, e.g. `/dev/drbd1000`.
4. Make that node Primary using `drbd <node> drbdadm primary $R`.
5. On that node, mount and work on it...

   ```sh
   sudo mkdir -p /mnt/breakglass
   sudo mount /dev/drbd1000 /mnt/breakglass
   ```

   Keep file ownership as the app expects it.
6. Unmount using `sudo umount /mnt/breakglass`, then hand it back using `drbd <node> drbdadm secondary $R`. `secondary` fails while it's still mounted.
7. Scale the app back up, and check every replica returns to `UpToDate`.

### After Losing a Node

A drain or clean reboot needs nothing. A power loss or hang does: the HA Controller replaces the pod within about 30 seconds, but Kubernetes won't detach the volume from the dead node for 6 minutes, so the new pod waits about 7 minutes in all.

1. If that wait is too long, first confirm the node really is off: unreachable over ssh and no lights, not just `NotReady`.
2. Taint it once it shows `NotReady`, and the volume detaches straight away...

   ```sh
   kubectl taint node <node> node.kubernetes.io/out-of-service=nodeshutdown:NoExecute
   ```

   DRBD quorum stops a cut-off node writing even if it's still alive, but only use this for a node you know is down.
3. When the node is back and `Ready`, remove the taint. It also evicted that node's satellite, so its replicas can't resync until it's gone...

   ```sh
   kubectl taint node <node> node.kubernetes.io/out-of-service=nodeshutdown:NoExecute-
   ```

4. Check every replica returns to `UpToDate`. A replica that missed writes catches up from the others. While the app keeps writing, DRBD holds a resync to about 10MB/s so the app comes first, under two minutes per GiB to catch up.
5. If LINSTOR refuses to place a volume on the node with "Not enough free space", and `lin storage-pool list` shows its `thin` pool at 0 KiB free, refresh the node using `lin node reconnect <node>`.

LINSTOR never evicts an offline node's replicas by itself (the operator disables it), so a node that's away for hours or days catches up when it returns.

### When Two Nodes Are Lost

The surviving copy loses quorum and freezes I/O instead of failing it. Pods using the volume hang but don't restart. etcd loses quorum too, so the Kubernetes API is down.

1. Bring one of the other nodes back. Frozen writes continue by themselves once it rejoins, with nothing lost.
2. **Don't force a lone copy to Primary.** If neither node can come back, recover etcd first using the [k3s etcd recovery](k3s-etcd-recovery.md) runbook.

### Rebuild a Replica

Use this when a node's copy is gone or can't be trusted.

1. Remove its disk using `lin resource delete <node> $R`. LINSTOR keeps a diskless tiebreaker there.
2. Add the disk back using `lin resource toggle-disk <node> $R --storage-pool thin`.
3. Watch it go from `SyncTarget` to `UpToDate` in `lin resource list -r $R`.

A rebuild copies only written data, at about 10s per GiB over 1GbE.

## Verify

- `lin resource list` shows every replica `UpToDate`. A `SyncTarget` that's still moving is fine; one stuck at the same percentage for several minutes isn't, so check `drbd <node> drbdsetup status $R --verbose --statistics` on a good copy.
- `kubectl describe nodes | grep out-of-service` prints nothing. If it prints a taint, remove it as in After Losing a Node.
- Any app scaled to 0 is back to its usual replicas, and its pods are `Running`.
