{{/*
Resource names key off .Release.Name, which the ApplicationSet sets to the
service name (e.g. quoteplus-frontend). So objects are quoteplus-frontend,
quoteplus-frontend-service, quoteplus-frontend-configmap - stable across
environments, distinguished by namespace. Do NOT introduce a names/appLabel
indirection - see gitops-mrea's mrea-api chart for why that's a trap.
*/}}
{{- define "quoteplus.name" -}}
{{ .Release.Name }}
{{- end -}}

{{- define "quoteplus.labels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: quoteplus
app.kubernetes.io/managed-by: argocd
{{- if .Values.env }}
quoteplus.mindcaninc.com/env: {{ .Values.env | quote }}
{{- end }}
{{- end -}}

{{- define "quoteplus.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}

{{/*
Fail loudly on an unset image tag rather than silently deploying :latest.
CI writes image.tag into values/tenants/<env>/<service>.yaml; an empty value
here means the pipeline did not run or wrote to the wrong path.
*/}}
{{- define "quoteplus.image" -}}
{{- $tag := required (printf "image.tag is required for %s - CI writes it into values/tenants/quoteplus-stage/%s.yaml" .Release.Name .Release.Name) .Values.image.tag -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end -}}
