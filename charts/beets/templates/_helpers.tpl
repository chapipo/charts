{{- define "beets.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "beets.fullname" -}}
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

{{- define "beets.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "beets.labels" -}}
helm.sh/chart: {{ include "beets.chart" . }}
{{ include "beets.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "beets.selectorLabels" -}}
app.kubernetes.io/name: {{ include "beets.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "beets.dataClaim" -}}
{{- .Values.persistence.data.existingClaim | default (printf "%s-data" (include "beets.fullname" .)) }}
{{- end }}

{{/*
Final beets config: user config + enforced safety settings.
Fails if the user tries to override a safety setting with an unsafe value.
*/}}
{{- define "beets.config" -}}
{{- $cfg := deepCopy .Values.config -}}
{{- $import := get $cfg "import" | default dict -}}
{{- range $k := list "move" "copy" "link" "hardlink" "reflink" }}
{{- if and (hasKey $import $k) (get $import $k) }}
{{- fail (printf "config.import.%s must stay off: Lidarr owns file names and folders" $k) }}
{{- end }}
{{- end }}
{{- range $k := list "quiet" "incremental" }}
{{- if and (hasKey $import $k) (not (get $import $k)) }}
{{- fail (printf "config.import.%s must stay on for unattended runs" $k) }}
{{- end }}
{{- end }}
{{- if eq (toString (get $import "duplicate_action" | default "ask")) "ask" }}
{{- fail "config.import.duplicate_action must be set and not \"ask\": nobody can answer the prompt in a CronJob" }}
{{- end }}
{{- range $k := list "directory" "library" "statefile" }}
{{- if hasKey $cfg $k }}
{{- fail (printf "config.%s is managed by the chart" $k) }}
{{- end }}
{{- end }}
{{- $forcedImport := dict "move" false "copy" false "link" false "hardlink" false "reflink" false "quiet" true "incremental" true "resume" false -}}
{{- $_ := set $cfg "import" (mergeOverwrite $import $forcedImport) -}}
{{- $_ := set $cfg "directory" .Values.persistence.music.mountPath -}}
{{- $_ := set $cfg "library" "/config/library.db" -}}
{{- $_ := set $cfg "statefile" "/config/state.pickle" -}}
{{- toYaml $cfg }}
{{- end }}
