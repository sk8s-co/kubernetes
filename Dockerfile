ARG KUBE_VERSION=1.35
ARG KUBE_VERSION_PATCH=0
ARG KUBE_VERSION_GO=1.25
ARG ETCD_VERSION=3.6.6

FROM quay.io/coreos/etcd:v${ETCD_VERSION} AS etcd

FROM golang:${KUBE_VERSION_GO}-alpine AS cloned
ARG KUBE_VERSION_GO \
    KUBE_VERSION \
    KUBE_VERSION_PATCH
ENV KUBE_VERSION_GO=${KUBE_VERSION_GO} \
    KUBE_VERSION=${KUBE_VERSION} \
    KUBE_VERSION_PATCH=${KUBE_VERSION_PATCH}

RUN apk add --no-cache git make bash npm jq gcc musl-dev coreutils 
RUN npm install -g semver@7

RUN git clone https://github.com/kubernetes/kubernetes.git -b v${KUBE_VERSION}.${KUBE_VERSION_PATCH} --depth=1 /kubernetes
WORKDIR /kubernetes

FROM cloned AS patched
COPY patches/ /patches/
COPY remote-patches/ /remote-patches/
COPY hack/apply-patches.sh /hack/apply-patches.sh
ENV PATCHES_DIR=/patches REMOTE_PATCHES_DIR=/remote-patches REMOTE_CACHE_DIR=/remote-cache
RUN /hack/apply-patches.sh all

FROM patched AS kube-apiserver
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kube-apiserver KUBE_STATIC_OVERRIDES=kube-apiserver && \
    mv /kubernetes/_output/local/go/bin/kube-apiserver /usr/local/bin/kube-apiserver

FROM patched AS kube-controller-manager
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kube-controller-manager KUBE_STATIC_OVERRIDES=kube-controller-manager && \
    mv /kubernetes/_output/local/go/bin/kube-controller-manager /usr/local/bin/kube-controller-manager

FROM patched AS kube-scheduler
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kube-scheduler KUBE_STATIC_OVERRIDES=kube-scheduler && \
    mv /kubernetes/_output/local/go/bin/kube-scheduler /usr/local/bin/kube-scheduler

FROM patched AS kubelet
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kubelet KUBE_STATIC_OVERRIDES=kubelet && \
    mv /kubernetes/_output/local/go/bin/kubelet /usr/local/bin/kubelet

FROM patched AS kubectl
ARG KUBE_VERSION
ENV KUBE_VERSION=${KUBE_VERSION}
RUN --mount=type=cache,id=go-${KUBE_VERSION},target=/go \
    CGO_ENABLED=0 make all WHAT=cmd/kubectl KUBE_STATIC_OVERRIDES=kubectl && \
    mv /kubernetes/_output/local/go/bin/kubectl /usr/local/bin/kubectl

FROM alpine AS smoke
COPY --from=etcd /usr/local/bin/etcd /kubernetes/etcd
COPY --from=etcd /usr/local/bin/etcdctl /kubernetes/etcdctl
COPY --from=kube-apiserver /usr/local/bin/kube-apiserver /kubernetes/kube-apiserver
COPY --from=kube-controller-manager /usr/local/bin/kube-controller-manager /kubernetes/kube-controller-manager
COPY --from=kube-scheduler /usr/local/bin/kube-scheduler /kubernetes/kube-scheduler
COPY --from=kubectl /usr/local/bin/kubectl /kubernetes/kubectl
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
