{{- define "todo-app.name" -}}
todo-app
{{- end -}}

{{- define "todo-app.labels" -}}
app.kubernetes.io/name: {{ include "todo-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "todo-app.backendImage" -}}
{{- required "backend.image.repository is required" .Values.backend.image.repository }}:{{ .Values.backend.image.tag }}
{{- end -}}

{{- define "todo-app.frontendImage" -}}
{{- required "frontend.image.repository is required" .Values.frontend.image.repository }}:{{ .Values.frontend.image.tag }}
{{- end -}}
