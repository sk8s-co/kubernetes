package main

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"time"

	apiversion "go.etcd.io/etcd/api/v3/version"
	clientv3 "go.etcd.io/etcd/client/v3"
	"go.etcd.io/etcd/server/v3/embed"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Println(apiversion.Version)
		return
	}

	// --- Etcd embedded config ---
	cfg := embed.NewConfig()
	cfg.Dir = "/tmp/etcd-data"
	cfg.Logger = "zap"    // modern logger
	cfg.LogLevel = "warn" // keep it quiet

	// single-node defaults
	lpurl := mustParseURL("http://127.0.0.1:2380", "peer")
	lcurl := mustParseURL("http://127.0.0.1:2379", "client")
	cfg.ListenPeerUrls = []url.URL{*lpurl}
	cfg.ListenClientUrls = []url.URL{*lcurl}
	cfg.AdvertisePeerUrls = []url.URL{*lpurl}
	cfg.AdvertiseClientUrls = []url.URL{*lcurl}
	cfg.InitialCluster = fmt.Sprintf("%s=%s", cfg.Name, lpurl.String())
	cfg.ClusterState = "new"

	// Optional: make it a bit more “dev friendly”
	cfg.AutoCompactionMode = "revision"
	cfg.AutoCompactionRetention = "1000"

	// --- Start embedded etcd ---
	e, err := embed.StartEtcd(cfg)
	if err != nil {
		log.Fatalf("failed to start embedded etcd: %v", err)
	}
	defer e.Close()

	// Wait until it's ready to serve client requests
	select {
	case <-e.Server.ReadyNotify():
		log.Println("embedded etcd is ready")
	case <-time.After(30 * time.Second):
		e.Server.Stop() // trigger shutdown
		log.Fatalf("etcd took too long to start")
	}

	// --- Create a v3 client pointed at our embedded server ---
	cli, err := clientv3.New(clientv3.Config{
		Endpoints:   []string{lcurl.String()},
		DialTimeout: 5 * time.Second,
	})
	if err != nil {
		log.Fatalf("failed to create etcd client: %v", err)
	}
	defer cli.Close()

	// --- Use it like normal etcd ---
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	_, err = cli.Put(ctx, "started-at", time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		log.Fatalf("put started-at failed: %v", err)
	}

	log.Println("ready; data dir:", mustAbs(cfg.Dir))
}

func mustAbs(p string) string {
	abs, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	return abs
}

func mustParseURL(raw, label string) *url.URL {
	u, err := url.Parse(raw)
	if err != nil {
		log.Fatalf("failed to parse %s url: %v", label, err)
	}
	return u
}
