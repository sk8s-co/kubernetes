ARG KUBE_VERSION=v1.34
ARG ETCD_VERSION=v3.6.6
ARG KUBERNETES_VERSION=${KUBE_VERSION}.0
ARG DASHBOARD_AUTH_VERSION=1.4.0
ARG DASHBOARD_WEB_VERSION=1.7.0
ARG DASHBOARD_API_VERSION=1.14.0
FROM quay.io/coreos/etcd:${ETCD_VERSION} AS etcdctl
FROM registry.k8s.io/kube-apiserver:${KUBERNETES_VERSION} AS kube-apiserver
FROM registry.k8s.io/kube-controller-manager:${KUBERNETES_VERSION} AS kube-controller-manager
FROM registry.k8s.io/kube-scheduler:${KUBERNETES_VERSION} AS kube-scheduler
FROM registry.k8s.io/kubectl:${KUBERNETES_VERSION} AS kubectl
FROM kubernetesui/dashboard-auth:${DASHBOARD_AUTH_VERSION} AS dashboard-auth
FROM kubernetesui/dashboard-web:${DASHBOARD_WEB_VERSION} AS dashboard-web
FROM kubernetesui/dashboard-api:${DASHBOARD_API_VERSION} AS dashboard-api

FROM golang:1.25 AS etcd
COPY cmd ./cmd
COPY go.mod ./go.mod
COPY go.sum ./go.sum
RUN CGO_ENABLED=0 go build -trimpath -ldflags '-s -w -extldflags "-static"' -o /usr/local/bin/etcd ./cmd/etcd

FROM alpine AS smoke
WORKDIR /kubernetes
COPY --from=etcd /usr/local/bin/etcd /kubernetes/etcd
COPY --from=etcdctl /usr/local/bin/etcdctl /kubernetes/etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubectl /bin/kubectl /kubernetes/kubectl
COPY --from=dashboard-auth /dashboard-auth /kubernetes/dashboard-auth
COPY --from=dashboard-api /dashboard-api /kubernetes/dashboard-api
COPY --from=dashboard-web /dashboard-web /kubernetes/dashboard-web
COPY --from=dashboard-web /locale_conf.json /kubernetes/locale_conf.json
COPY --from=dashboard-web /public /kubernetes/public

RUN ["/kubernetes/etcd", "version"]
RUN ["/kubernetes/etcdctl", "version"]
RUN ["/kubernetes/kube-apiserver", "--version"]
RUN ["/kubernetes/kube-controller-manager", "--version"]
RUN ["/kubernetes/kube-scheduler", "--version"]
RUN ["/kubernetes/kubectl", "version", "--client"]

FROM alpine
COPY --from=smoke /kubernetes /kubernetes
