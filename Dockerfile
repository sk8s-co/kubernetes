ARG ETCD_VERSION=v3.6.6
ARG KUBE_VERSION=v1.34.0
ARG DASHBOARD_AUTH_VERSION=1.4.0
ARG DASHBOARD_WEB_VERSION=1.7.0
ARG DASHBOARD_API_VERSION=1.14.0
FROM quay.io/coreos/etcd:${ETCD_VERSION} AS etcdctl
FROM registry.k8s.io/kube-apiserver:${KUBE_VERSION} AS kube-apiserver
FROM registry.k8s.io/kube-controller-manager:${KUBE_VERSION} AS kube-controller-manager
FROM registry.k8s.io/kube-scheduler:${KUBE_VERSION} AS kube-scheduler
FROM registry.k8s.io/kubectl:${KUBE_VERSION} AS kubectl
FROM kubernetesui/dashboard-auth:${DASHBOARD_AUTH_VERSION} AS dashboard-auth
FROM kubernetesui/dashboard-web:${DASHBOARD_WEB_VERSION} AS dashboard-web
FROM kubernetesui/dashboard-api:${DASHBOARD_API_VERSION} AS dashboard-api
FROM ghcr.io/scaffoldly/procfiled:beta AS procfiled

FROM golang:1.25 AS etcd
COPY cmd ./cmd
COPY go.mod ./go.mod
COPY go.sum ./go.sum
RUN CGO_ENABLED=0 go build -trimpath -ldflags '-s -w -extldflags "-static"' -o /usr/local/bin/etcd ./cmd/etcd

FROM alpine/openssl AS certs
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout sk8s.key \
    -out sk8s.crt \
    -subj '/CN=localhost' \
    -addext 'subjectAltName=IP:127.0.0.1,DNS:localhost,DNS:host.docker.internal' \
    -days 3650
RUN openssl rsa -in sk8s.key -pubout -out sk8s.pub

FROM kubectl AS kubeconfig
COPY --from=certs sk8s.crt sk8s.crt
COPY --from=certs sk8s.key sk8s.key
COPY --from=certs sk8s.pub sk8s.pub
RUN ["kubectl", "config", "set-cluster", "sk8s", "--server=https://localhost:6443", "--certificate-authority=sk8s.crt", "--kubeconfig=kubeconfig", "--embed-certs=true"]
RUN ["kubectl", "config", "set-credentials", "sk8s", "--client-certificate=sk8s.crt", "--client-key=sk8s.key", "--kubeconfig=kubeconfig", "--embed-certs=true"]
RUN ["kubectl", "config", "set-context", "sk8s", "--cluster=sk8s", "--user=sk8s", "--kubeconfig=kubeconfig"]
RUN ["kubectl", "config", "use-context", "sk8s", "--kubeconfig=kubeconfig"]

FROM alpine AS smoke
WORKDIR /sk8s
COPY --from=etcd /usr/local/bin/etcd etcd
COPY --from=etcdctl /usr/local/bin/etcdctl etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler kube-scheduler
COPY --from=kubectl /bin/kubectl kubectl
COPY --from=procfiled /usr/local/bin/procfiled procfiled
COPY --from=dashboard-auth /dashboard-auth dashboard-auth
COPY --from=dashboard-api /dashboard-api dashboard-api
COPY --from=dashboard-web /dashboard-web dashboard-web
COPY --from=dashboard-web /locale_conf.json locale_conf.json
COPY --from=dashboard-web /public public
COPY --from=certs --chmod=644 sk8s.key sk8s.key
COPY --from=certs --chmod=644 sk8s.crt sk8s.crt
COPY --from=certs --chmod=644 sk8s.pub sk8s.pub
COPY --from=kubeconfig --chmod=644 kubeconfig kubeconfig
COPY Procfile Procfile

RUN ["/sk8s/etcd", "version"]
RUN ["/sk8s/etcdctl", "version"]
RUN ["/sk8s/kube-apiserver", "--version"]
RUN ["/sk8s/kube-controller-manager", "--version"]
RUN ["/sk8s/kube-scheduler", "--version"]
RUN ["/sk8s/kubectl", "version", "--client"]
RUN ["/sk8s/procfiled", "--version"]

FROM alpine

RUN apk add --no-cache bash

WORKDIR /sk8s
ENV PATH="/sk8s:${PATH}" \
    KUBECONFIG="/sk8s/kubeconfig"

COPY --from=smoke /sk8s /sk8s

ENTRYPOINT [ "procfiled" ]
CMD [ "start", "-j", "/sk8s/Procfile" ]
