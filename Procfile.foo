etcd!: /bin/etcd
kube-apiserver!: kube-apiserver --advertise-address=0.0.0.0 --bind-address=0.0.0.0 --disable-http2-serving --etcd-servers=http://localhost:2379 --tls-cert-file=sk8s.crt --tls-private-key-file=sk8s.key --client-ca-file=sk8s.crt --service-account-key-file=sk8s.crt --service-account-signing-key-file=sk8s.key --service-account-issuer=https://kubernetes.default.svc.cluster.local --allow-privileged=true --kubelet-client-certificate=sk8s.crt --kubelet-client-key=sk8s.key --v=1
dashboard-auth!: dashboard-auth --kubeconfig=/var/task/kubeconfig --address 0.0.0.0 --port 8000 -v=4
dashboard-api!: dashboard-api --kubeconfig=/var/task/kubeconfig --insecure-bind-address 0.0.0.0 --insecure-port 8010 --metrics-provider=none -v=4
dashboard-web!: dashboard-web --kubeconfig=/var/task/kubeconfig --insecure-bind-address 0.0.0.0 --insecure-port 8020 -v=4
