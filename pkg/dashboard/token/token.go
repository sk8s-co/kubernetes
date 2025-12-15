package token

import (
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"k8s.io/dashboard/web/pkg/router"
	"k8s.io/klog/v2"
)

func init() {
	router.Root().Use(tokenMiddleware())
}

func tokenMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		token := c.Query("token")

		if token == "" {
			c.Next()
			return
		}

		// Parse token to get exp claim
		maxAge, ok := maxAge(token)
		if !ok {
			// Token is unparseable, do nothing
			c.Next()
			return
		}

		// Check if request is over HTTPS (either directly or via proxy)
		secure := c.Request.TLS != nil || c.GetHeader("X-Forwarded-Proto") == "https"

		// Set token as a cookie
		c.SetCookie(
			"token", // name
			token,   // value
			maxAge,  // maxAge (calculated from exp claim)
			"/",     // path
			"",      // domain (empty = current domain)
			secure,  // secure (true if HTTPS)
			true,    // httpOnly
		)

		// Build redirect URL without token parameter
		redirectURL := c.Request.URL
		query := redirectURL.Query()
		query.Del("token")
		redirectURL.RawQuery = query.Encode()

		// Redirect to same path without token parameter
		c.Redirect(http.StatusFound, redirectURL.String())
		c.Abort()
	}
}

func maxAge(token string) (int, bool) {
	// Split JWT token into parts
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		klog.V(2).Info("Token is not a valid JWT format, skipping cookie")
		return 0, false
	}

	// Decode the payload (second part)
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		klog.V(2).InfoS("Failed to decode token payload, skipping cookie", "error", err)
		return 0, false
	}

	// Parse JSON payload
	var claims struct {
		Exp int64 `json:"exp"`
	}
	if err := json.Unmarshal(payload, &claims); err != nil {
		klog.V(2).InfoS("Failed to parse token claims, skipping cookie", "error", err)
		return 0, false
	}

	// Check if exp claim exists
	if claims.Exp == 0 {
		klog.V(2).Info("Token has no exp claim, skipping cookie")
		return 0, false
	}

	// Calculate maxAge from exp
	now := time.Now().Unix()
	maxAge := int(claims.Exp - now)

	// Ensure maxAge is positive
	if maxAge <= 0 {
		klog.V(2).Info("Token has already expired, skipping cookie")
		return 0, false
	}

	klog.V(2).InfoS("Calculated cookie maxAge from token exp", "maxAge", maxAge)
	return maxAge, true
}
