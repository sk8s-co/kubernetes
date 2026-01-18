ARG KUBE_VERSION=1.34
ARG KUBE_VERSION_PATCH=0
ARG KUBE_VERSION_GO=1.24
ARG ETCD_VERSION=3.6.6

FROM quay.io/coreos/etcd:v${ETCD_VERSION} AS etcd
FROM registry.k8s.io/kube-controller-manager:v${KUBE_VERSION}.${KUBE_VERSION_PATCH} AS kube-controller-manager
FROM registry.k8s.io/kube-scheduler:v${KUBE_VERSION}.${KUBE_VERSION_PATCH} AS kube-scheduler
FROM registry.k8s.io/kubectl:v${KUBE_VERSION}.${KUBE_VERSION_PATCH} AS kubectl

FROM golang:${KUBE_VERSION_GO}-alpine AS builder
ARG KUBE_VERSION_GO \
    KUBE_VERSION \
    KUBE_VERSION_PATCH
ENV KUBE_VERSION_GO=${KUBE_VERSION_GO} \
    KUBE_VERSION=${KUBE_VERSION} \
    KUBE_VERSION_PATCH=${KUBE_VERSION_PATCH}
RUN apk add --no-cache git make bash
RUN git clone https://github.com/kubernetes/kubernetes.git -b v${KUBE_VERSION}.${KUBE_VERSION_PATCH} --depth=1 /kubernetes
WORKDIR /kubernetes

COPY patches/${KUBE_VERSION}/*.patch /patches/
RUN set -e && for patch in /patches/*.patch; do \
    echo "Applying patch: $patch" && \
    git apply --verbose --check "$patch" && \
    git apply --verbose "$patch"; \
    done && \
    echo "=== Applied patches ===" && \
    git diff HEAD && \
    git config user.email "build@localhost" && \
    git config user.name "Build" && \
    git add -A && git commit -m "Apply patches"

FROM builder AS kube-apiserver
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kube-apiserver KUBE_STATIC_OVERRIDES=kube-apiserver && \
    mv /kubernetes/_output/local/go/bin/kube-apiserver /usr/local/bin/kube-apiserver

FROM builder AS kubelet
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kubelet KUBE_STATIC_OVERRIDES=kubelet && \
    mv /kubernetes/_output/local/go/bin/kubelet /usr/local/bin/kubelet

FROM alpine AS smoke
COPY --from=etcd /usr/local/bin/etcd /kubernetes/etcd
COPY --from=etcd /usr/local/bin/etcdctl /kubernetes/etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubectl /bin/kubectl /kubernetes/kubectl
COPY --from=kubelet /usr/local/bin/kubelet /kubernetes/kubelet

RUN ["/kubernetes/etcd", "--version"]
RUN ["/kubernetes/etcdctl", "version"]
RUN ["/kubernetes/kube-apiserver", "--version"]
RUN ["/kubernetes/kube-controller-manager", "--version"]
RUN ["/kubernetes/kube-scheduler", "--version"]
RUN ["/kubernetes/kubectl", "version", "--client"]
RUN ["/kubernetes/kubelet", "--version"]

FROM scratch
COPY --from=smoke /kubernetes/* /
