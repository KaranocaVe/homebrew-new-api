class NewApi < Formula
  desc "Self-hosted AI API gateway with an embedded web console"
  homepage "https://github.com/QuantumNous/new-api"
  url "https://github.com/QuantumNous/new-api/archive/refs/tags/v1.0.0-rc.47.tar.gz"
  sha256 "6e718051ca5c753005be9378425517523c49fe4d6345b572efa822a24dfea391"
  license "AGPL-3.0-only"

  livecheck do
    url "https://github.com/QuantumNous/new-api/releases"
    regex(%r{href=.*?/releases/tag/v?(\d+(?:\.\d+)+(?:-rc\.\d+)?)}i)
  end

  depends_on "bun" => :build
  depends_on "go" => :build
  depends_on arch: :arm64

  patch :DATA

  def install
    odie "New API is supported on macOS only" unless OS.mac?

    cd "web" do
      ENV["CI"] = ""
      ENV["DISABLE_ESLINT_PLUGIN"] = "true"
      ENV["VITE_REACT_APP_VERSION"] = version.to_s
      system "bun", "install", "--frozen-lockfile"
      system "bun", "run", "build"
    end

    ldflags = "-s -w -X github.com/QuantumNous/new-api/common.Version=#{version}"
    system "go", "mod", "download"
    system "go", "build", "-trimpath", "-ldflags", ldflags, "-o", bin/"new-api", "."

    service_script = Pathname(__FILE__).realpath.dirname.parent/"libexec/new-api-service"
    libexec.install service_script
    chmod 0755, libexec/"new-api-service"

    (bin/"new-api-init").write <<~BASH
      #!/bin/bash
      set -euo pipefail
      export NEW_API_HOME="#{var}/new-api"
      exec "#{opt_libexec}/new-api-service" --init-only
    BASH
    (bin/"new-api-init").chmod 0755
  end

  post_install_steps do
    mkdir_p "new-api/logs", base: :var
    set_permissions "new-api", "700", base: :var, recursive: false
  end

  service do
    run [opt_libexec/"new-api-service"]
    keep_alive true
    working_dir var/"new-api"
    environment_variables NEW_API_HOME:   var/"new-api",
                          NEW_API_BINARY: opt_bin/"new-api",
                          PATH:           std_service_path_env
    log_path var/"new-api/logs/stdout.log"
    error_log_path var/"new-api/logs/stderr.log"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/new-api --version")
  end
end

__END__
diff --git a/main.go b/main.go
index 0000000..0000000 100644
--- a/main.go
+++ b/main.go
@@ -6,6 +6,7 @@ import (
 	"embed"
 	"errors"
 	"fmt"
 	"log"
+	"net"
 	"net/http"
 	"os"
 	"os/signal"
@@ -60,6 +61,11 @@ func main() {
 	if err != nil {
 		common.FatalLog(common.LogText("failed to initialize resources: %s", err.Error()))
 		return
 	}
+	bindAddress := os.Getenv("BIND_ADDRESS")
+	if bindAddress == "" {
+		bindAddress = "127.0.0.1"
+	}
 
 	common.SysLog(common.LogText("New API %s started", common.Version))
@@ -166,7 +172,7 @@ func main() {
 	if os.Getenv("ENABLE_PPROF") == "true" {
 		gopool.Go(func() {
-			log.Println(http.ListenAndServe("0.0.0.0:8005", nil))
+			log.Println(http.ListenAndServe(net.JoinHostPort(bindAddress, "8005"), nil))
 		})
 		go common.Monitor()
@@ -208,7 +214,7 @@ func main() {
 	}
 
 	srv := &http.Server{
-		Addr:    ":" + port,
+		Addr:    net.JoinHostPort(bindAddress, port),
 		Handler: server,
 	}
