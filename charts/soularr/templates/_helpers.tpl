{{- define "soularr.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "soularr.fullname" -}}
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

{{- define "soularr.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "soularr.labels" -}}
helm.sh/chart: {{ include "soularr.chart" . }}
{{ include "soularr.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "soularr.selectorLabels" -}}
app.kubernetes.io/name: {{ include "soularr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* True when at least one API key must be stored in the chart's own Secret */}}
{{- define "soularr.needsSecret" -}}
{{- if or (not .Values.apiKeys.lidarr.existingSecret.name) (not .Values.apiKeys.slskd.existingSecret.name) -}}
true
{{- end -}}
{{- end }}

{{/*
env entry for an API key: secretKeyRef to the existing Secret, or to the chart's Secret.
Usage: include "soularr.apiKeyEnv" (dict "root" . "envName" "LIDARR_API_KEY" "cfg" .Values.apiKeys.lidarr "chartKey" "lidarr-api-key")
*/}}
{{- define "soularr.apiKeyEnv" -}}
- name: {{ .envName }}
  valueFrom:
    secretKeyRef:
      {{- if .cfg.existingSecret.name }}
      name: {{ .cfg.existingSecret.name }}
      key: {{ required (printf "apiKeys: existingSecret.key is required for %s" .envName) .cfg.existingSecret.key }}
      {{- else }}
      name: {{ include "soularr.fullname" .root }}
      key: {{ .chartKey }}
      {{- end }}
{{- end }}

{{/*
One INI value: lists joined with ",", booleans as True/False.
Helm parses numbers as float64 and would print 1048576 as 1.048576e+06:
whole numbers are printed as integers.
*/}}
{{- define "soularr.iniValue" -}}
{{- if kindIs "slice" . -}}
{{- join "," . -}}
{{- else if kindIs "bool" . -}}
{{- ternary "True" "False" . -}}
{{- else if kindIs "float64" . -}}
{{- if eq . (float64 (int64 .)) -}}{{ int64 . }}{{- else -}}{{ . }}{{- end -}}
{{- else -}}
{{- toString . -}}
{{- end -}}
{{- end }}

{{/* Full config.ini */}}
{{- define "soularr.configIni" -}}
{{- range $section, $keys := .Values.config }}
[{{ $section }}]
{{- if or (eq $section "Lidarr") (eq $section "Slskd") }}
{{- if hasKey $keys "api_key" }}
{{- fail (printf "config.%s.api_key must not be set: use apiKeys instead" $section) }}
{{- end }}
api_key = ${{ printf "{%s_API_KEY}" (upper $section) }}
{{- end }}
{{- range $k, $v := $keys }}
{{ $k }} = {{ include "soularr.iniValue" $v }}
{{- end }}
{{ end }}
{{- end }}
