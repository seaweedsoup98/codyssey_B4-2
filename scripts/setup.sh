#!/usr/bin/env bash
# Prepare the supplied Linux application without running it.
set -euo pipefail
umask 077

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux ]] || fail 'Linux is required.'
(( EUID != 0 )) || fail 'Run as a non-root user.'
for command_name in unzip chmod mkdir mktemp mv grep; do
    command -v "$command_name" >/dev/null || fail "Missing command: $command_name"
done

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
archive=${1:-$repo_dir/agent-app-leak.zip}
export AGENT_HOME=${AGENT_HOME:-$HOME/agent-leak-lab}
[[ $AGENT_HOME = /* ]] || fail 'AGENT_HOME must be an absolute path.'
[[ -f $archive ]] || fail "Missing $archive (download the supplied file from Codyssey)."

case $(uname -m) in
    x86_64) executable=agent-leak-app-x86 ;;
    aarch64|arm64) executable=agent-leak-app-arm64 ;;
    *) fail "Unsupported architecture: $(uname -m)" ;;
esac

# Search by basename because the ZIP may contain an enclosing directory.
mapfile -t matches < <(unzip -Z1 "$archive" | grep -E "(^|/)${executable}$" || true)
[[ ${#matches[@]} == 1 ]] || fail "Expected one $executable entry in the ZIP."

export AGENT_PORT=15034
export AGENT_UPLOAD_DIR="$AGENT_HOME/upload_files"
export AGENT_KEY_PATH="$AGENT_HOME/api_keys"
export AGENT_LOG_DIR="$AGENT_HOME/logs"
export AGENT_BINARY="$AGENT_HOME/agent-leak-app"
mkdir -p "$AGENT_HOME" "$AGENT_UPLOAD_DIR" "$AGENT_KEY_PATH" "$AGENT_LOG_DIR"

# Do not replace existing keys with a different value.
if [[ -e $AGENT_KEY_PATH/secret.key || -L $AGENT_KEY_PATH/secret.key ]]; then
    [[ -f $AGENT_KEY_PATH/secret.key && ! -L $AGENT_KEY_PATH/secret.key ]] || fail 'Invalid secret.key file.'
    [[ $(cat "$AGENT_KEY_PATH/secret.key") == agent_api_key_test ]] || fail 'Existing secret.key differs.'
else
    printf 'agent_api_key_test\n' > "$AGENT_KEY_PATH/secret.key"
fi
chmod 600 "$AGENT_KEY_PATH/secret.key"

[[ ! -L $AGENT_BINARY ]] || fail 'Executable must not be a symlink.'
if [[ ! -f $AGENT_BINARY ]]; then
    tmp=$(mktemp "$AGENT_HOME/.binary.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    unzip -p "$archive" "${matches[0]}" > "$tmp"
    chmod 700 "$tmp"
    mv "$tmp" "$AGENT_BINARY"
    trap - EXIT
fi
[[ -x $AGENT_BINARY ]] || fail 'The executable is not runnable.'
# Refuse to run a stale executable from another ZIP.
installed_hash=$(sha256sum "$AGENT_BINARY" | awk '{print $1}')
archive_hash=$(unzip -p "$archive" "${matches[0]}" | sha256sum | awk '{print $1}')
[[ $installed_hash == "$archive_hash" ]] || fail 'Installed binary differs from the supplied ZIP.'

# %q escapes spaces and shell metacharacters in user-selected paths.
{
    printf 'export AGENT_HOME=%q\n' "$AGENT_HOME"
    printf 'export AGENT_PORT=%q\n' "$AGENT_PORT"
    printf 'export AGENT_UPLOAD_DIR=%q\n' "$AGENT_UPLOAD_DIR"
    printf 'export AGENT_KEY_PATH=%q\n' "$AGENT_KEY_PATH"
    printf 'export AGENT_LOG_DIR=%q\n' "$AGENT_LOG_DIR"
    printf 'export AGENT_BINARY=%q\n' "$AGENT_BINARY"
} > "$AGENT_HOME/agent.env"

printf 'Prepared: %s\nLoad settings: source %q\n' "$AGENT_BINARY" "$AGENT_HOME/agent.env"
printf 'The application has not been started or verified.\n'
