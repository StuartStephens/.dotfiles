import os
import platform
import shutil
import subprocess

home_dir = os.path.expanduser("~")
local_bin = os.path.join(home_dir, ".local", "bin")
opencode_bin = os.path.join(home_dir, ".opencode", "bin")
android_sdk_root = "/opt/homebrew/share/android-commandlinetools"
android_emulator_bin = os.path.join(android_sdk_root, "emulator")
android_platform_tools = os.path.join(android_sdk_root, "platform-tools")
android_studio_jbr = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"

if os.path.isdir(android_sdk_root):
    $ANDROID_SDK_ROOT = android_sdk_root
    $ANDROID_HOME = android_sdk_root

if os.path.isdir(android_studio_jbr):
    $JAVA_HOME = android_studio_jbr

path_entries = (
    os.path.join(android_studio_jbr, "bin"),
    android_platform_tools,
    android_emulator_bin,
    opencode_bin,
    local_bin,
    "/home/linuxbrew/.linuxbrew/bin",  # Linux homebrew
    "/home/linuxbrew/.linuxbrew/sbin",
    "/opt/homebrew/bin",  # macOS homebrew
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

# On Linux, point at the systemd user ssh-agent socket.
# On macOS, launchd manages this automatically — don't override it.
if platform.system() == "Linux":
    $SSH_AUTH_SOCK = f"/run/user/{os.getuid()}/ssh-agent.socket"

def _ssh_login(args, stdin=None):
    """Load SSH key into agent with 8-hour timeout."""
    ssh-add -t 8h ~/.ssh/id_ed25519
    ssh-add -l

aliases['ssh-login'] = _ssh_login
