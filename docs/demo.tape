# docs/demo.tape — record a real Cyber-LLM session as a GIF.
#
# Usage:
#   1. Install vhs:  https://github.com/charmbracelet/vhs
#   2. Put a valid ANTHROPIC_API_KEY in .env and install the deps
#      (see the README "Install" section).
#   3. From the project root:  vhs docs/demo.tape
#      -> produces docs/demo.gif
#
# The tape assumes a Unix shell (use WSL on Windows). It launches the CLI,
# pastes a short nmap result, waits for the model's answer, then quits.

Output docs/demo.gif

Set Shell "bash"
Set FontSize 18
Set Width 1100
Set Height 720
Set Padding 16

Type "python -m src.cli"
Enter
Sleep 2s

Type "22/tcp  open  ssh      OpenSSH 7.6p1"
Enter
Type "80/tcp  open  http     Apache httpd 2.4.29"
Enter
Type "445/tcp open  smb      Samba smbd 4.7.6"
Enter
Type "END"
Enter

Sleep 10s

Type "quit"
Enter
Sleep 1s
