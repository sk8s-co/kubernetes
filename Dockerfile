ARG KUBE_VERSION=v1.34
ARG ETCD_VERSION=v3.6.6
ARG KUBERNETES_VERSION=${KUBE_VERSION}.0

FROM quay.io/coreos/etcd:${ETCD_VERSION} AS etcd
FROM registry.k8s.io/kube-apiserver:${KUBERNETES_VERSION} AS kube-apiserver
FROM registry.k8s.io/kube-controller-manager:${KUBERNETES_VERSION} AS kube-controller-manager
FROM registry.k8s.io/kube-scheduler:${KUBERNETES_VERSION} AS kube-scheduler
FROM registry.k8s.io/kubectl:${KUBERNETES_VERSION} AS kubectl

FROM alpine AS smoke
COPY --from=etcd /usr/local/bin/etcd /kubernetes/etcd
COPY --from=etcd /usr/local/bin/etcdctl /kubernetes/etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubectl /bin/kubectl /kubernetes/kubectl

RUN ["/kubernetes/etcd", "--version"]
RUN ["/kubernetes/etcdctl", "version"]
RUN ["/kubernetes/kube-apiserver", "--version"]
RUN ["/kubernetes/kube-controller-manager", "--version"]
RUN ["/kubernetes/kube-scheduler", "--version"]
RUN ["/kubernetes/kubectl", "version", "--client"]

FROM alpine
COPY --from=smoke /kubernetes /kubernetes
