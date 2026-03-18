#!/bin/bash
# Stremio Launcher for Raspberry Pi (arm64)
# Starts the Node.js streaming server, waits for it to be ready,
# then launches the Stremio shell UI.
# All components are expected in /opt/stremio/

STREMIO_DIR="/opt/stremio"
SERVER_JS="${STREMIO_DIR}/server.js"
STREMIO_BIN="${STREMIO_DIR}/stremio"
LOG_DIR="${HOME}/.local/share/Smart Code ltd/stremio-server"
SERVER_LOG="${LOG_DIR}/server.log"

# Find node: prefer bundled, then system
find_node() {
    if [ -x "${STREMIO_DIR}/node" ]; then
        echo "${STREMIO_DIR}/node"
    elif command -v node >/dev/null 2>&1; then
        command -v node
    elif command -v nodejs >/dev/null 2>&1; then
        command -v nodejs
    else
        return 1
    fi
}

NODE_BIN="$(find_node)" || {
    echo "Error: Node.js not found. Install nodejs or ensure ${STREMIO_DIR}/node exists." >&2
    exit 1
}

if [ ! -f "${SERVER_JS}" ]; then
    echo "Error: server.js not found at ${SERVER_JS}" >&2
    exit 1
fi

if [ ! -x "${STREMIO_BIN}" ]; then
    echo "Error: stremio binary not found at ${STREMIO_BIN}" >&2
    exit 1
fi

# Create log directory
mkdir -p "${LOG_DIR}"

# Check if the server is already running on port 11470
server_already_running() {
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ':11470 ' && return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -q ':11470 ' && return 0
    fi
    # Fallback: try to connect
    if command -v curl >/dev/null 2>&1; then
        curl -s --max-time 1 http://127.0.0.1:11470/ >/dev/null 2>&1 && return 0
    fi
    return 1
}

SERVER_PID=""

# Cleanup function to kill background server on exit
cleanup() {
    if [ -n "${SERVER_PID}" ] && kill -0 "${SERVER_PID}" 2>/dev/null; then
        kill "${SERVER_PID}" 2>/dev/null
        wait "${SERVER_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if server_already_running; then
    echo "Streaming server already running on port 11470."
else
    # Start the streaming server in background
    echo "Starting Stremio streaming server..."
    "${NODE_BIN}" "${SERVER_JS}" > "${SERVER_LOG}" 2>&1 &
    SERVER_PID=$!

    # Wait for server to be ready (max 60 seconds, RPi can be slow)
    TIMEOUT=120
    ELAPSED=0
    SERVER_READY=false

    while [ ${ELAPSED} -lt ${TIMEOUT} ]; do
        # Check if server process is still running
        if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
            echo "Error: Streaming server exited unexpectedly. Check ${SERVER_LOG}" >&2
            cat "${SERVER_LOG}" >&2
            exit 1
        fi

        # Check if the server has started
        if grep -q "EngineFS server started at" "${SERVER_LOG}" 2>/dev/null; then
            SERVER_READY=true
            break
        fi

        sleep 0.5
        ELAPSED=$((ELAPSED + 1))
    done

    if [ "${SERVER_READY}" = false ]; then
        echo "Warning: Server did not signal ready within ${TIMEOUT}s, launching Stremio anyway..."
    else
        SERVER_ADDR=$(grep "EngineFS server started at" "${SERVER_LOG}" 2>/dev/null | head -1 | sed 's/EngineFS server started at //')
        echo "Streaming server ready at ${SERVER_ADDR}"
    fi
fi

# Launch Stremio shell
echo "Launching Stremio..."
exec "${STREMIO_BIN}" "$@"
