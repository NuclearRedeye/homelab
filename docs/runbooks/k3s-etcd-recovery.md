# k3s etcd Recovery

Recovering the k3s cluster after a node's hardware fails, quorum is lost, or data needs rolling back.

## When to Use

- A node's hardware has failed and it needs repairing and reinstalling.
- etcd has lost quorum: fewer than a majority of its members are up, and the API no longer responds.
- Data has been deleted or damaged, and the cluster needs rolling back to a snapshot.

## When Not to Use

- After a power cut, no action is needed: the cluster resumes once a majority of etcd members are up.
- A node that's briefly down, e.g. for a reboot, rejoins by itself.

## Before You Start

- Run `kubectl` from the dev shell. If the server your kubeconfig points at is down, add `--server https://<host>:6443` for one that's up. Find the current one using...

  ```sh
  kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'
  ```
- Have ssh and sudo on each node.

## Steps

### Replace a Failed Node

1. Stop k3s on it using `sudo systemctl stop k3s`.
2. Remove its old etcd member using `kubectl delete node <host>`.
3. Once repaired, reinstall it using First Install in the [README](../../README.md). Its host key is new, so update its key in `.sops.yaml` and run `sops updatekeys secrets/k3s.yaml`.
4. Deploy it, and it rejoins through its `serverAddr`.

### Recover From Lost Quorum

1. On one surviving node, reset etcd to make it a one-member cluster...

   ```sh
   sudo systemctl stop k3s
   sudo k3s server --cluster-reset
   sudo systemctl start k3s
   ```

2. On each other node, wipe its etcd data so it rejoins...

   ```sh
   sudo systemctl stop k3s
   sudo rm -rf /var/lib/rancher/k3s/server/db
   sudo systemctl start k3s
   ```

   Its `serverAddr` must point at a node that's up, so rejoin in that order, temporarily changing a `serverAddr` to the reset node if none point at it.

### Restore a Snapshot

1. Find the snapshot on the node that took it using `sudo k3s etcd-snapshot list`.
2. Stop k3s on every node using `sudo systemctl stop k3s`.
3. On that node, restore it and start k3s...

   ```sh
   sudo k3s server --cluster-reset \
     --cluster-reset-restore-path=<snapshot> \
     --token-file /run/secrets/k3s_token
   sudo systemctl start k3s
   ```

4. Rejoin the other nodes as in step 2 of Recover From Lost Quorum.

## Verify

- `kubectl get nodes` shows every node `Ready`.
- `kubectl get nodes -l node-role.kubernetes.io/etcd` lists every etcd member.
