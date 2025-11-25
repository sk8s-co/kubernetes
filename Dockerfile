ARG ETCD_VERSION=v3.6.6
ARG KUBE_VERSION=v1.34.0
FROM quay.io/coreos/etcd:${ETCD_VERSION} AS etcdctl
FROM registry.k8s.io/kube-apiserver:${KUBE_VERSION} AS kube-apiserver
FROM registry.k8s.io/kube-controller-manager:${KUBE_VERSION} AS kube-controller-manager
FROM registry.k8s.io/kube-scheduler:${KUBE_VERSION} AS kube-scheduler
FROM registry.k8s.io/kubectl:${KUBE_VERSION} AS kubectl
FROM ghcr.io/scaffoldly/procfiled:beta AS procfiled

FROM golang:1.25 AS etcd
COPY cmd ./cmd
COPY go.mod ./go.mod
COPY go.sum ./go.sum
RUN CGO_ENABLED=0 go build -trimpath -ldflags '-s -w -extldflags "-static"' -o /usr/local/bin/etcd ./cmd/etcd

FROM alpine AS smoke
COPY --from=etcd /usr/local/bin/etcd /bin/etcd
COPY --from=etcdctl /usr/local/bin/etcdctl /bin/etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver /bin/kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager /bin/kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler /bin/kube-scheduler
COPY --from=kubectl /bin/kubectl /bin/kubectl
COPY --from=procfiled /usr/local/bin/procfiled /bin/procfiled

RUN ["/bin/etcd", "version"]
RUN ["/bin/etcdctl", "version"]
RUN ["/bin/kube-apiserver", "--version"]
RUN ["/bin/kube-controller-manager", "--version"]
RUN ["/bin/kube-scheduler", "--version"]
RUN ["/bin/kubectl", "version", "--client"]
RUN ["/bin/procfiled", "--version"]

FROM alpine/openssl AS certs
RUN openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout tls.key \
    -out tls.crt \
    -subj "/CN=kube-apiserver"
RUN openssl genrsa -out sa.key 2048 && \
    openssl rsa -in sa.key -pubout -out sa.pub

FROM alpine
WORKDIR /var/task

COPY --from=smoke /bin/etcdctl /bin/etcdctl
COPY --from=smoke /bin/etcd /bin/etcd
COPY --from=smoke /bin/kube-apiserver /bin/kube-apiserver
COPY --from=smoke /bin/kube-controller-manager /bin/kube-controller-manager
COPY --from=smoke /bin/kube-scheduler /bin/kube-scheduler
COPY --from=smoke /bin/kubectl /bin/kubectl
COPY --from=smoke /bin/procfiled /bin/procfiled
COPY --from=certs tls.crt /var/task/tls.crt
COPY --from=certs tls.key /var/task/tls.key
COPY --from=certs sa.key /var/task/sa.key
COPY --from=certs sa.pub /var/task/sa.pub

COPY Procfile Procfile
ENTRYPOINT [ "procfiled" ]
CMD [ "start", "-j", "/var/task/Procfile" ]
