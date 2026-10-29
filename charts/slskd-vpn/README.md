# slskd-vpn

Helm chart for [slskd](https://github.com/slskd/slskd) (Soulseek client) with a
[Gluetun](https://github.com/qdm12/gluetun) sidecar: all slskd traffic goes through the VPN,
with a kill switch, and the Soulseek listen port automatically follows the port forwarded by the VPN.

Structure inspired by the [rtomik qbittorrent-vpn chart](https://github.com/rtomik/helm-charts/tree/main/charts/qbittorrent-vpn) (MIT license).

## Differences from qbittorrent-vpn

| | qbittorrent-vpn | slskd-vpn |
|---|---|---|
| Gluetun | regular container | **native sidecar**: starts before slskd, stops after it |
| App startup | does not wait for the VPN | slskd waits until the tunnel is healthy (gluetun startup probe) |
| Privileged mode | `privileged: true` | `NET_ADMIN` only |
| App user | root | UID 1000 (same as Lidarr and Soularr) |
| App DNS | cluster DNS (outside the tunnel) | gluetun DNS, **inside** the tunnel |
| Gluetun control server | no authentication | protected by an API key |
| Port forwarding | manual | **native slskd ↔ gluetun integration** |
| Secrets | plain values or existing Secret | generated automatically and kept across upgrades, or existing Secret |

## Requirements

- **Kubernetes 1.29 or later** for the native sidecar. On older clusters, set `gluetun.nativeSidecar: false`.
- **A VPN with port forwarding.** In gluetun: ProtonVPN, Private Internet Access, Perfect Privacy, PrivateVPN.
  - ProtonVPN with WireGuard: generate the configuration with **NAT-PMP (Port Forwarding)** enabled.
  - ProtonVPN with OpenVPN: append `+pmp` to the username.
- **Shared storage** for downloads and music, via NFS or `ReadWriteMany` PVCs.
  It must be owned by UID/GID 1000: `fsGroup` does not apply to NFS.
- **Pod Security**: if your namespace enforces the `baseline` or `restricted` level, gluetun's
  `NET_ADMIN` capability will be rejected. Label the namespace as `privileged`.
- **k3s nodes running in a Proxmox LXC container**: `/dev/net/tun` must be exposed to the LXC container
  (see the [gluetun tun errors page](https://github.com/qdm12/gluetun-wiki/blob/main/errors/tun.md)),
  then enable `gluetun.tunHostPath`.

## Installation

Create a minimal `my-values.yaml`:

```yaml
secrets:
  values:
    soulseekUsername: my-username
    soulseekPassword: my-password
    wireguardPrivateKey: "wireguard-private-key="

gluetun:
  vpn:
    provider: protonvpn
    serverCountries: "France,Switzerland"

slskd:
  persistence:
    downloads:
      nfs: { server: 192.168.1.10, path: /export/downloads }
    shares:
      - name: music
        mountPath: /music
        readOnly: true
        nfs: { server: 192.168.1.10, path: /export/music }

ingress:
  enabled: true
  className: traefik
  hosts:
    - host: slskd.example.lan
      paths: [{ path: /, pathType: Prefix }]
```

Then:

```sh
helm install slskd-vpn ./slskd-vpn -n music --create-namespace -f my-values.yaml
```

Name the release `slskd-vpn`: resources will then simply be called `slskd-vpn`.

To keep secrets out of values, create a Secret with the keys `soulseek-username`,
`soulseek-password`, `web-username`, `web-password`, `api-key`, `gluetun-api-key` and
`wireguard-private-key` (or `openvpn-username` / `openvpn-password`), and set its name in
`secrets.existingSecret`.

## Connecting Soularr

In Soularr's `config.ini`, `[Slskd]` section:

- `host_url`: `http://slskd-vpn.music.svc.cluster.local:5030`
- `api_key`: the value returned by the command shown after installation (step 3 of the notes)
- `download_dir`: `/downloads/slskd`, mounted at the same path in Lidarr and Soularr

By default the API key is restricted to the k3s pod network (`slskd.apiKey.cidr: 10.42.0.0/16`)
with the `ReadWrite` role. If Soularr gets a 403 error, switch the role to `Administrator`.

## Checking that traffic goes through the VPN

The notes shown after installation give the commands to read the public IP and the forwarded
port from the gluetun container. The gluetun image ships `wget`, not `curl`.

## Caveats

- **The forwarded port changes** with each new VPN session. slskd follows the change on its own.
- **One forwarded port per ProtonVPN session.** Do not share slskd's gluetun with a torrent client:
  use one gluetun per P2P application.
- **Soulseek searches and ProtonVPN WireGuard**: one user reports gluetun turning unhealthy
  during searches ([gluetun #2875](https://github.com/qdm12/gluetun/discussions/2875)), with no known fix so far.
- **ProtonVPN WireGuard keys** must be renewed every year.
- **UI edits**: settings passed as environment variables take precedence over `slskd.yml`.

## Validation status

The chart was rendered with several value sets (WireGuard and OpenVPN, native sidecar or not,
existing Secret, no VPN) and the manifests were validated against the official Kubernetes 1.31
JSON schemas, plus consistency checks (volumes, ports, selectors, `$(…)` variables).
It has **not been deployed on a real cluster yet**: run `helm template`, then a test install.

## Sources

- [slskd – configuration (environment variables)](https://github.com/slskd/slskd/blob/master/docs/config.md)
- [slskd – VPN integration](https://github.com/slskd/slskd/blob/master/docs/vpn.md)
- [gluetun wiki – ProtonVPN](https://github.com/qdm12/gluetun-wiki/blob/main/setup/providers/protonvpn.md)
- [gluetun wiki – control server](https://github.com/qdm12/gluetun-wiki/blob/main/setup/advanced/control-server.md)
- [K8s native sidecar with VPN](https://nerdiverset.no/k8s-native-sidecar-with-vpn/)
- [rtomik/helm-charts – qbittorrent-vpn](https://github.com/rtomik/helm-charts/tree/main/charts/qbittorrent-vpn)
