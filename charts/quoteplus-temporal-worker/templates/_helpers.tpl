{{/*
Same convention as charts/quoteplus-framework/templates/_helpers.tpl -
resource names key off .Release.Name (quoteplus-temporal-worker).
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
CI (Jenkins, owned by DevOps per QTP-867) writes image.tag into
values/tenants/quoteplus-stage/quoteplus-temporal-worker.yaml once it
publishes a build - it hasn't yet.
*/}}
{{- define "quoteplus.image" -}}
{{- $tag := required (printf "image.tag is required for %s - CI writes it into values/tenants/quoteplus-stage/%s.yaml once quoteplus-dev/quoteplus-temporal-worker-dev is published" .Release.Name .Release.Name) .Values.image.tag -}}
{{ .Values.image.repository }}:{{ $tag }}
{{- end -}}
