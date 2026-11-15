# release-argus

Helm chart for [Argus](https://release-argus.io) ([source](https://github.com/release-argus/Argus)):
it watches software releases (GitHub, URLs, ...), shows them in a web UI, and can send
notifications or call webhooks when a new version comes out.

## Design choices

- **The config is kept in a Secret.** `config.yml` is rendered from `config.content` into a
  Secret, because it often contains notification tokens and webhook secrets.
- **The web UI can still edit the config.** An init container (`seed-config`) copies the
  config from the Secret into the data volume (`/app/data/config.yml`) **only if no config
  exists there yet**. Changes made through the web UI are kept across restarts. Set
  `config.overwrite: true` to make `values.yaml` the source of truth instead: the config is then
  replaced on every pod start and web UI changes are lost.
- **Changing the config restarts the pod.** The Deployment carries a checksum of the Secret,
  so `helm upgrade` with new config values rolls the pod. Without `config.overwrite`, the new
  values are still **not** applied if a config already exists in the volume.
- **Single pod, `Recreate` strategy.** Argus stores its state in a SQLite database
  (`/app/data/argus.db`) on a `ReadWriteOnce` volume, so two pods must never run at the same time.
  Keep `replicaCount: 1`.
- **The image starts as root.** Its entrypoint fixes file ownership, then drops privileges to
  `argus.uid`/`argus.gid` (911 by default). Do not set `runAsNonRoot` unless you handle file
  ownership yourself.

## Installation

Minimal `my-values.yaml`:

```yaml
config:
  content:
    settings:
      log:
        level: INFO
      web:
        listen_host: 0.0.0.0
        listen_port: "8080"
    service:
      release-argus:
        latest_version:
          type: github
          url: release-argus/Argus

storage:
  size: 1Gi
```

```sh
helm install release-argus ./release-argus -n argus --create-namespace -f my-values.yaml
```

If you change `service.port`, set `config.content.settings.web.listen_port` to the same value:
the container port, the probes and the Service all use `service.port`.

## Configuration

`config.content` is written as-is to `config.yml`. See the
[Argus configuration docs](https://release-argus.io/docs/config/) for every option.

| Parameter | Description | Default |
|---|---|---|
| `image.repository` | Argus image | `releaseargus/argus` |
| `image.tag` | Image tag | chart `appVersion` |
| `argus.uid` / `argus.gid` | UID/GID the Argus process runs as | `911` / `911` |
| `argus.extraArgs` | Extra flags for the `argus` binary (e.g. `-log.level=DEBUG`) | `[]` |
| `config.overwrite` | Replace the config in the volume on every pod start | `false` |
| `config.content` | Content of `config.yml` | see `values.yaml` |
| `service.type` / `service.port` | Service type and port (also the container port) | `ClusterIP` / `8080` |
| `storage.size` | Size of the data PVC | `1Gi` |
| `storage.storageClassName` | Storage class (empty = cluster default) | `""` |
| `storage.accessModes` | PVC access modes | `[ReadWriteOnce]` |
| `storage.annotations` | PVC annotations | `{}` |
| `ingress.enabled` | Create an Ingress | `false` |
| `httpRoute.enabled` | Create a Gateway API HTTPRoute | `false` |
| `sidecars` | Extra containers in the Argus pod (templated with `tpl`) | `[]` |
| `resources`, `nodeSelector`, `tolerations`, `affinity` | Usual pod settings | `{}` / `[]` |

## Exposing the web UI

By default the web UI is only reachable inside the cluster:

```sh
kubectl -n argus port-forward svc/release-argus 8080:8080
```

### Ingress

```yaml
ingress:
  enabled: true
  className: nginx
  hosts:
    - host: argus.example.com
      paths:
        - path: /
          pathType: Prefix
```

### HTTPRoute (Gateway API)

Requires the Gateway API CRDs and an existing Gateway. The chart always generates the
`backendRefs` pointing to the Argus Service; you only set `matches` and `filters`.

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: gateway
      namespace: gateway-system
      sectionName: https
  hostnames:
    - argus.example.com
```

Argus has optional basic auth (`settings.web.basic_auth` in the config). Enable it, or put an
authentication layer in front, before exposing the web UI outside your network.

## Sidecars

`sidecars` is a list of containers added to the Argus pod. It is rendered with `tpl`, so it can
use template expressions. Sidecars can mount the `data` volume (config and database):

```yaml
sidecars:
  - name: watcher
    image: busybox:1.36
    command: ["sh", "-c", "while true; do ls -l /app/data; sleep 3600; done"]
    env:
      - name: RELEASE
        value: "{{ .Release.Name }}"
    volumeMounts:
      - name: data
        mountPath: /app/data
        readOnly: true
```

## Upgrading the config

Without `config.overwrite`, changes to `config.content` are only used for a fresh volume. To apply
them to an existing install, either edit the config from the web UI, or run one upgrade with
`--set config.overwrite=true`.
