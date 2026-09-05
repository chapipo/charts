{{/*
Base chart name
*/}}
{{- define "proxbox-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Full release name (prefixed by the Helm release name)
*/}}
{{- define "proxbox-api.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "proxbox-api.labels" -}}
app.kubernetes.io/name: {{ include "proxbox-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{/*
Selector labels (used by the Service to match Pods)
*/}}
{{- define "proxbox-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "proxbox-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
