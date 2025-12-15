package main

import (
	"crypto/elliptic"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"k8s.io/klog/v2"

	"k8s.io/dashboard/certificates"
	"k8s.io/dashboard/certificates/ecdsa"
	"k8s.io/dashboard/client"
	"k8s.io/dashboard/web/pkg/args"
	"k8s.io/dashboard/web/pkg/environment"
	"k8s.io/dashboard/web/pkg/router"

	// Importing route packages forces route registration
	_ "k8s.io/dashboard/web/pkg/config"
	_ "k8s.io/dashboard/web/pkg/locale"
	_ "k8s.io/dashboard/web/pkg/settings"
	_ "k8s.io/dashboard/web/pkg/systembanner"
)

func init() {
	router.Root().Use(func(c *gin.Context) {
		token := c.Query("token")

		if token == "" {
			c.Next()
			return
		}

		// Calculate maxAge from JWT exp claim, or 0 if invalid
		maxAge := 0
		parts := strings.Split(token, ".")
		if len(parts) != 3 {
			maxAge = 0
		}
		payload, err := base64.RawURLEncoding.DecodeString(parts[1])
		if err != nil {
			maxAge = 0
		}
		var claims struct {
			Exp int64 `json:"exp"`
		}
		if json.Unmarshal(payload, &claims) != nil {
			maxAge = 0
		}
		if claims.Exp == 0 {
			maxAge = 0
		}
		age := int(claims.Exp - time.Now().Unix())
		maxAge = max(0, age)
		c.SetCookie("token", token, maxAge, "/", "", c.GetHeader("X-Forwarded-Proto") == "https", true)

		redirectURL := c.Request.URL
		query := redirectURL.Query()
		query.Del("token")
		redirectURL.RawQuery = query.Encode()
		c.Redirect(http.StatusFound, redirectURL.String())
		c.Abort()
	})
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		fmt.Println(environment.Version)
		return
	}

	klog.InfoS("Starting Kubernetes Dashboard Web", "version", environment.Version)

	client.Init(
		client.WithUserAgent(environment.UserAgent()),
		client.WithKubeconfig(args.KubeconfigPath()),
	)

	certCreator := ecdsa.NewECDSACreator(args.KeyFile(), args.CertFile(), elliptic.P256())
	certManager := certificates.NewCertManager(certCreator, args.DefaultCertDir(), args.AutoGenerateCertificates())
	certPath, keyPath, err := certManager.GetCertificatePaths()
	if err != nil {
		klog.Fatalf("Error while loading dashboard server certificates. Reason: %s", err)
	}

	if len(certPath) != 0 && len(keyPath) != 0 {
		klog.V(1).InfoS("Listening and serving securely on", "address", args.Address())
		if err := router.Router().RunTLS(args.Address(), certPath, keyPath); err != nil {
			klog.Fatalf("Router error: %s", err)
		}
	} else {
		klog.V(1).InfoS("Listening and serving insecurely on", "address", args.InsecureAddress())
		if err := router.Router().Run(args.InsecureAddress()); err != nil {
			klog.Fatalf("Router error: %s", err)
		}
	}
}
