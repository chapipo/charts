{{- define "slskd-vpn.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "slskd-vpn.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "slskd-vpn.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "slskd-vpn.labels" -}}
helm.sh/chart: {{ include "slskd-vpn.chart" . }}
{{ include "slskd-vpn.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "slskd-vpn.selectorLabels" -}}
app.kubernetes.io/name: {{ include "slskd-vpn.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Name of the Secret in use (provided or created by the chart) */}}
{{- define "slskd-vpn.secretName" -}}
{{- if .Values.secrets.existingSecret }}
{{- .Values.secrets.existingSecret }}
{{- else }}
{{- printf "%s-secrets" (include "slskd-vpn.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Base64-encoded secret value:
provided value > value already in the cluster Secret > generated value.
Usage: include "slskd-vpn.secretValue" (dict "provided" X "existing" $data "key" "k" "length" 32)
*/}}
{{- define "slskd-vpn.secretValue" -}}
{{- if .provided }}
{{- .provided | b64enc }}
{{- else if and .existing (hasKey .existing .key) }}
{{- index .existing .key }}
{{- else }}
{{- randAlphaNum (int .length) | b64enc }}
{{- end }}
{{- end }}

{{/* Reference to a Secret key, for an env block */}}
{{- define "slskd-vpn.secretRef" -}}
valueFrom:
  secretKeyRef:
    name: {{ include "slskd-vpn.secretName" .root }}
    key: {{ .key }}
{{- end }}

{{/* gluetun container (used as a native init container or as a regular container) */}}
{{- define "slskd-vpn.gluetunContainer" -}}
{{- $g := .Values.gluetun -}}
- name: gluetun
  image: "{{ $g.image.repository }}:{{ $g.image.tag }}"
  imagePullPolicy: {{ $g.image.pullPolicy }}
  {{- if $g.nativeSidecar }}
  restartPolicy: Always
  {{- end }}
  securityContext:
    {{- toYaml $g.securityContext | nindent 4 }}
  env:
    - name: TZ
      value: {{ .Values.slskd.timezone | quote }}
    - name: VPN_SERVICE_PROVIDER
      value: {{ $g.vpn.provider | quote }}
    - name: VPN_TYPE
      value: {{ $g.vpn.type | quote }}
    {{- with $g.vpn.serverCountries }}
    - name: SERVER_COUNTRIES
      value: {{ . | quote }}
    {{- end }}
    {{- with $g.vpn.serverCities }}
    - name: SERVER_CITIES
      value: {{ . | quote }}
    {{- end }}
    {{- with $g.vpn.serverHostnames }}
    - name: SERVER_HOSTNAMES
      value: {{ . | quote }}
    {{- end }}
    {{- if eq $g.vpn.type "wireguard" }}
    - name: WIREGUARD_PRIVATE_KEY
      {{- include "slskd-vpn.secretRef" (dict "root" . "key" "wireguard-private-key") | nindent 6 }}
    {{- with $g.vpn.wireguard.addresses }}
    - name: WIREGUARD_ADDRESSES
      value: {{ . | quote }}
    {{- end }}
    {{- else if eq $g.vpn.type "openvpn" }}
    - name: OPENVPN_USER
      {{- include "slskd-vpn.secretRef" (dict "root" . "key" "openvpn-username") | nindent 6 }}
    - name: OPENVPN_PASSWORD
      {{- include "slskd-vpn.secretRef" (dict "root" . "key" "openvpn-password") | nindent 6 }}
    {{- else }}
    {{- fail "gluetun.vpn.type must be wireguard or openvpn" }}
    {{- end }}
    - name: VPN_PORT_FORWARDING
      value: {{ ternary "on" "off" $g.vpn.portForwarding | quote }}
    {{- if $g.vpn.portForwardOnly }}
    - name: PORT_FORWARD_ONLY
      value: "on"
    {{- end }}
    - name: FIREWALL_INPUT_PORTS
      value: {{ prepend $g.extraInputPorts .Values.slskd.webPort | join "," | quote }}
    {{- with $g.outboundSubnets }}
    - name: FIREWALL_OUTBOUND_SUBNETS
      value: {{ . | quote }}
    {{- end }}
    - name: HTTP_CONTROL_SERVER_ADDRESS
      value: {{ printf ":%v" $g.controlServer.port | quote }}
    # Control server key, reused below through $(...) expansion
    - name: CONTROL_APIKEY_RAW
      {{- include "slskd-vpn.secretRef" (dict "root" . "key" "gluetun-api-key") | nindent 6 }}
    - name: HTTP_CONTROL_SERVER_AUTH_DEFAULT_ROLE
      value: {{ `{"auth":"apikey","apikey":"$(CONTROL_APIKEY_RAW)"}` | quote }}
    {{- range $k, $v := $g.settings }}
    - name: {{ $k }}
      value: {{ $v | quote }}
    {{- end }}
    {{- with $g.extraEnv }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  ports:
    - name: control
      containerPort: {{ $g.controlServer.port }}
      protocol: TCP
  {{- if $g.startupProbe.enabled }}
  startupProbe:
    exec:
      command: ["/gluetun-entrypoint", "healthcheck"]
    periodSeconds: {{ $g.startupProbe.periodSeconds }}
    timeoutSeconds: {{ $g.startupProbe.timeoutSeconds }}
    failureThreshold: {{ $g.startupProbe.failureThreshold }}
  {{- end }}
  volumeMounts:
    {{- if $g.persistence.enabled }}
    - name: gluetun-data
      mountPath: /gluetun
    {{- end }}
    {{- if $g.tunHostPath }}
    - name: tun
      mountPath: /dev/net/tun
    {{- end }}
  resources:
    {{- toYaml $g.resources | nindent 4 }}
{{- end }}

{{/* Share volume: existing PVC or NFS */}}
{{- define "slskd-vpn.shareVolume" -}}
- name: share-{{ .share.name }}
  {{- if .share.existingClaim }}
  persistentVolumeClaim:
    claimName: {{ .share.existingClaim }}
    readOnly: {{ .share.readOnly | default false }}
  {{- else if and .share.nfs .share.nfs.server }}
  nfs:
    server: {{ .share.nfs.server }}
    path: {{ required (printf "slskd.persistence.shares[%s].nfs.path is required" .share.name) .share.nfs.path }}
    readOnly: {{ .share.readOnly | default false }}
  {{- else }}
  {{- fail (printf "Share %q must set existingClaim or nfs.server" .share.name) }}
  {{- end }}
{{- end }}
