{{/*
ABOUTME: Standard Helm template helpers for the hello-regulated chart.
ABOUTME: Provides reusable snippets for naming, labels, and selector labels.
*/}}

{{/*
Expand the name of the chart.
Truncated to 63 characters because Kubernetes name fields are limited to this length.
*/}}
{{- define "hello-regulated.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this
(by the DNS naming spec). If release name contains chart name it will be used as
a full name.
*/}}
{{- define "hello-regulated.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "hello-regulated.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources. These follow the Kubernetes recommended
label conventions (app.kubernetes.io/*) for consistent resource identification
across tools like kubectl, Helm, and monitoring systems.
*/}}
{{- define "hello-regulated.labels" -}}
helm.sh/chart: {{ include "hello-regulated.chart" . }}
{{ include "hello-regulated.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels used in Deployment matchLabels and Service selectors.
These must be immutable after creation -- do not include version or chart labels
here, as they change on upgrade and would break rolling updates.
*/}}
{{- define "hello-regulated.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hello-regulated.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
