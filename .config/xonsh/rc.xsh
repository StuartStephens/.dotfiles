import os
import shutil
import subprocess

if '/home/stuart/.local/bin' not in $PATH:
    $PATH.insert(0, '/home/stuart/.local/bin')

home_dir = os.path.expanduser("~")
local_bin = os.path.join(home_dir, ".local", "bin")
opencode_bin = os.path.join(home_dir, ".opencode", "bin")

path_entries = (
    opencode_bin,
    local_bin,
    "/opt/homebrew/bin",
    "/opt/homebrew/sbin",
    "/usr/local/bin",
    "/usr/local/sbin",
)

for path_entry in reversed(path_entries):
    if os.path.isdir(path_entry) and path_entry not in $PATH:
        $PATH.insert(0, path_entry)

os.environ["PATH"] = os.pathsep.join($PATH)

if $XONSH_INTERACTIVE:
    $SHELL_TYPE = "prompt_toolkit"
    $XONSH_PROMPT_AUTO_SUGGEST = True
    $AUTO_SUGGEST_IN_COMPLETIONS = True
    $COMPLETION_MODE = "menu-complete"
    $COMPLETIONS_DISPLAY = "multi"
    $CASE_SENSITIVE_COMPLETIONS = False
    $SUBSEQUENCE_PATH_COMPLETION = True

    fastfetch_bin = shutil.which("fastfetch")
    if fastfetch_bin:
        subprocess.run([fastfetch_bin], check=False)

$UE_ROOT = os.path.join(home_dir, "Apps", "Unreal")
$SDL_VIDEODRIVER = "x11"

# Always point at the systemd user ssh-agent socket so every shell (and
# any process launched from it, e.g. nvim) can reach the agent without
# needing to run ssh-login first.
$SSH_AUTH_SOCK = f"/run/user/{os.getuid()}/ssh-agent.socket"

def _ssh_login(args, stdin=None):
    """Load SSH key into agent with 8-hour timeout."""
    ssh-add -t 8h ~/.ssh/id_ed25519
    ssh-add -l

aliases['ssh-login'] = _ssh_login
