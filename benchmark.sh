#!/usr/bin/env bash
set -euo pipefail

export DURATION=10
export CONNECTIONS=200
BASE_URL="http://127.0.0.1:8080"
RESULTS_DIR="$(dirname "$0")/results"
SERVER_PID=""
SUITE_FILES=()

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        echo "Stopping server (PID $SERVER_PID)..."
        kill -- -"$SERVER_PID" 2>/dev/null || kill "$SERVER_PID" 2>/dev/null || true
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

build_python() {
    echo "Setting up Python Django server..."
    if [ ! -d "python-django/venv" ]; then
        python3 -m venv python-django/venv
    fi
    python-django/venv/bin/pip install -q -r python-django/requirements.txt
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

start_python() {
    build_python
    PYTHONPATH=python-django python-django/venv/bin/gunicorn benchmark.wsgi:application \
        --bind 0.0.0.0:8080 --workers "$(nproc)" &
    SERVER_PID=$!
}

start_bun() {
    echo "Starting Bun server..."
    bun js-bun/server.js &
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
    SUITE_FILES+=("$outfile")
}

generate_summary() {
    local outfile="$RESULTS_DIR/summary_$(date +%Y%m%d_%H%M%S).md"

    awk '
    function comma(n,    s, i, len) {
        s = sprintf("%.0f", n)
        len = length(s)
        for (i = len - 3; i > 0; i -= 3)
            s = substr(s, 1, i) "," substr(s, i + 1)
        return s
    }
    function print_table(title, data, suffix,    i, e) {
        printf "## %s\n\n", title
        printf "| Endpoint |"
        for (i = 1; i <= sc; i++) printf " %s |", dname[srv[i]]
        printf "\n|----------|"
        for (i = 1; i <= sc; i++) printf "-------:|"
        printf "\n"
        for (e = 1; e <= 3; e++) {
            printf "| %s |", elabel[e]
            for (i = 1; i <= sc; i++) {
                if (suffix == "rps")
                    printf " %s |", comma(data[srv[i], eid[e]])
                else
                    printf " %s ms |", data[srv[i], eid[e]]
            }
            printf "\n"
        }
        printf "\n"
    }
    BEGIN {
        dname["rust-axum"] = "Rust Axum"
        dname["js-bun"] = "JS Bun"
        dname["go-chi"] = "Go Chi"
        dname["java-quarkus"] = "Java Quarkus"
        dname["python-django"] = "Python Django"
        eid[1] = "health"; elabel[1] = "GET /api/health"
        eid[2] = "books";  elabel[2] = "GET /api/books"
        eid[3] = "book3";  elabel[3] = "GET /api/books/3"
        sc = 0
    }
    /^Benchmark:/ {
        s = $2
        if (!(s in seen)) { seen[s] = 1; sc++; srv[sc] = s }
    }
    /^=== .* GET \/api\/health/    { ep = "health" }
    /^=== .* GET \/api\/books ===$/ { ep = "books" }
    /^=== .* GET \/api\/books\//   { ep = "book3" }
    /Requests\/sec:/ { rps[s, ep] = $2 }
    /^  Average:/ { avg[s, ep] = $2 }
    /99\.00% in/ { p99[s, ep] = $3 }
    END {
        printf "# Benchmark Results\n\n"
        printf "- **Duration:** %s per endpoint\n", ENVIRON["DURATION"] "s"
        printf "- **Connections:** %s\n\n", ENVIRON["CONNECTIONS"]
        print_table("Requests/sec", rps, "rps")
        print_table("Average Latency", avg, "ms")
        print_table("p99 Latency", p99, "ms")
    }
    ' "$@" > "$outfile"

    echo ""
    echo "########################################"
    echo "  Summary saved to: $outfile"
    echo "########################################"
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
    echo "  4) Python Django"
    echo "  5) JS Bun"
    echo "  6) All (sequential)"
    echo ""
    read -rp "Choose [1-6]: " choice

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
            start_python
            wait_for_server
            run_suite "python-django"
            ;;
        5)
            start_bun
            wait_for_server
            run_suite "js-bun"
            ;;
        6)
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
            cleanup

            sleep 1

            start_python
            wait_for_server
            run_suite "python-django"
            cleanup

            sleep 1

            start_bun
            wait_for_server
            run_suite "js-bun"

            generate_summary "${SUITE_FILES[@]}"
            ;;
        *)
            echo "Invalid choice."
            exit 1
            ;;
    esac
}

main
