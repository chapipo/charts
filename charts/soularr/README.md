# soularr

Helm chart for [Soularr](https://github.com/mrusse/soularr): it reads the albums Lidarr wants,
searches them on Soulseek through [slskd](https://github.com/slskd/slskd), downloads them,
then asks Lidarr to import the result.

Designed to work with the `slskd-vpn` chart and the k8s-home-lab Lidarr chart.

## Design choices

- **No secrets in config.ini.** `config.ini` is rendered into a ConfigMap from `values.yaml`.
  The API keys are written as `${LIDARR_API_KEY}` and `${SLSKD_API_KEY}`, which Soularr expands
  from the environment when it reads the file. The environment variables come from Secrets.
- **The web UI cannot leak the keys.** The Soularr web UI has no authentication and its
  `/api/config` route returns (and can overwrite) `config.ini`. Soularr is started with
  `--config-dir /config --var-dir /data`: the web UI only looks for `config.ini` in `/data`,
  so it never sees the real file.
- **Same UID/GID as Lidarr and slskd (1000).** Soularr's README requires it, otherwise imports fail.
- **Pinned, versioned image** from GHCR (`ghcr.io/mrusse/soularr:1.2.3`). Docker Hub only gets
  `latest` and branch-name tags.
- **Numbers stay numbers.** Helm reads numbers as floats and would print `1048576` as
  `1.048576e+06`; the chart prints whole numbers as integers so Soularr can parse them.

## Requirements

- Lidarr and slskd running, with their API keys.
- The download area shared by slskd, Lidarr and Soularr (NFS or a `ReadWriteMany` PVC),
  owned by UID/GID 1000.

## Installation

Minimal `my-values.yaml`, with slskd installed from the `slskd-vpn` chart as release `slskd-vpn`:

```yaml
apiKeys:
  lidarr:
    existingSecret:
      name: lidarr-api-key     # kubectl create secret generic lidarr-api-key --from-literal=key=...
      key: key
  slskd:
    existingSecret:
      name: slskd-vpn-secrets  # created by the slskd-vpn chart
      key: api-key

persistence:
  downloads:
    nfs:
      server: 192.168.1.10
      path: /export/downloads
```

```sh
helm install soularr ./soularr -n music -f my-values.yaml
```

You can also put the keys directly in `apiKeys.<name>.value`; the chart then stores them in its
own Secret. Prefer existing Secrets so the keys stay out of your values files.

## Paths

| Setting | Meaning | Default |
|---|---|---|
| `config.Lidarr.download_dir` | slskd download folder **as Lidarr sees it** | `/downloads/slskd` |
| `config.Slskd.download_dir` | slskd download folder **as slskd and Soularr see it** | `/downloads/slskd` |
| `persistence.downloads.mountPath` | where Soularr mounts the shared download area | `/downloads` |

With the same export mounted at `/downloads` in slskd, Lidarr and Soularr, both paths are identical.

## Configuration

Every `config.ini` section is a map under `config`. Lists are joined with commas and booleans
become `True`/`False`. Setting `api_key` there is rejected on purpose. See Soularr's
[README](https://github.com/mrusse/soularr/blob/main/README.md) for the meaning of each option.

## Web UI

Enabled by default, reachable only inside the cluster (`kubectl port-forward`, see the install notes).
If you enable the Ingress, protect it with an authentication layer (for example a Traefik
forward-auth middleware): the web UI itself has none.

## Validation status

The chart was rendered in several scenarios (keys from the chart Secret or from existing Secrets,
existing PVCs, Ingress, web UI disabled) and validated against the official Kubernetes 1.31 JSON
schemas. The generated `config.ini` was read with Soularr's own interpolation logic, checking every
typed read (`getint`, `getfloat`, `getboolean`) that `soularr.py` performs. It has **not been deployed
on a real cluster yet**: run `helm template`, then a test install.

## Sources

- [Soularr – README, Dockerfile, run.sh, soularr.py, webui](https://github.com/mrusse/soularr)
- [Soularr – Docker publishing workflow (GHCR semver tags)](https://github.com/mrusse/soularr/blob/main/.github/workflows/docker.yaml)
- [Helm issue #1707: numbers parsed as float64 end up in scientific notation](https://github.com/helm/helm/issues/1707)
