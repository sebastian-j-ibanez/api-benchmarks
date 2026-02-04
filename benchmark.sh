#!/usr/bin/env bash
set -euo pipefail

DURATION=10
CONNECTIONS=200
BASE_URL="http://127.0.0.1:8080"
RESULTS_DIR="$(dirname "$0")/results"
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        echo "Stopping server (PID $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
        SERVER_PID=""
    fi
}
trap cleanup EXIT

check_deps() {
    if ! command -v oha &>/dev/null; then
        echo "Error: 'oha' is not installed."
        echo "Install it with: sudo pacman -S oha"
        exit 1
    fi
}

wait_for_server() {
    echo "Waiting for server on :8080..."
    for i in $(seq 1 30); do
        if curl -sf "$BASE_URL/api/health" &>/dev/null; then
            echo "Server is ready."
            return 0
        fi
        sleep 0.2
    done
    echo "Error: server did not start in time."
    exit 1
}

build_go() {
    echo "Building Go Chi server..."
    (cd go-chi && go build -o server .)
}

build_rust() {
    echo "Building Rust Axum server (release)..."
    (cd rust-axum && cargo build --release 2>&1 | tail -1)
}

build_java() {
    echo "Building Java Quarkus server..."
    (cd java-quarkus && ./mvnw package -DskipTests -q 2>&1 | tail -5)
}

start_go() {
    build_go
    ./go-chi/server &
    SERVER_PID=$!
}

start_rust() {
    build_rust
    ./rust-axum/target/release/rust-axum &
    SERVER_PID=$!
}

start_java() {
    build_java
    java -jar java-quarkus/target/quarkus-app/quarkus-run.jar &
    SERVER_PID=$!
}

run_bench() {
    local label="$1"
    local url="$2"
    echo ""
    echo "=== $label ==="
    echo "    URL: $url | Connections: $CONNECTIONS | Duration: ${DURATION}s"
    echo ""
    oha -z "${DURATION}s" -c "$CONNECTIONS" --no-tui "$url"
}

run_suite() {
    local name="$1"
    local outfile="$RESULTS_DIR/${name}_$(date +%Y%m%d_%H%M%S).txt"

    echo ""
    echo "########################################"
    echo "  Benchmarking: $name"
    echo "  Duration: ${DURATION}s per endpoint"
    echo "  Connections: $CONNECTIONS"
    echo "########################################"

    {
        echo "Benchmark: $name"
        echo "Date: $(date -Iseconds)"
        echo "Duration: ${DURATION}s | Connections: $CONNECTIONS"
        echo ""

        run_bench "$name - GET /api/health"    "$BASE_URL/api/health"
        echo ""
        run_bench "$name - GET /api/books"     "$BASE_URL/api/books"
        echo ""
        run_bench "$name - GET /api/books/3"   "$BASE_URL/api/books/3"
    } 2>&1 | tee "$outfile"

    echo ""
    echo "Results saved to: $outfile"
}

main() {
    cd "$(dirname "$0")"
    check_deps
    mkdir -p "$RESULTS_DIR"

    echo "==========================="
    echo "  HTTP Benchmark Suite"
    echo "==========================="
    echo ""
    echo "  1) Go Chi"
    echo "  2) Rust Axum"
    echo "  3) Java Quarkus"
    echo "  4) All (sequential)"
    echo ""
    read -rp "Choose [1-4]: " choice

    case "$choice" in
        1)
            start_go
            wait_for_server
            run_suite "go-chi"
            ;;
        2)
            start_rust
            wait_for_server
            run_suite "rust-axum"
            ;;
        3)
            start_java
            wait_for_server
            run_suite "java-quarkus"
            ;;
        4)
            start_go
            wait_for_server
            run_suite "go-chi"
            cleanup

            sleep 1

            start_rust
            wait_for_server
            run_suite "rust-axum"
            cleanup

            sleep 1

            start_java
            wait_for_server
            run_suite "java-quarkus"
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
}

main
