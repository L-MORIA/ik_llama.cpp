# Desktop shortcut — one-click server start

A Windows shortcut on the desktop launches the ik_llama.cpp server without
opening a terminal by hand. It is environment-specific (absolute paths to this
repo and the user profile), so the `.lnk` binary is **not** committed — only
the recipe to recreate it. The icon assets are committed under
`personal/assets/`.

## Target

- **Shortcut name:** `Qwen3.8 ik-server.lnk`
- **Location:** `C:\Users\User\Desktop\`
- **Command:** `cmd /c "F:/ik_llama.cpp/run_ik_qwen38.bat"`
- **Icon:** `F:/ik_llama.cpp/personal/assets/ik_qwen_icon.ico`
- **Behavior:** window starts minimized; server runs until closed.

## Recreate it (PowerShell)

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut(
        "$env:USERPROFILE\Desktop\Qwen3.8 ik-server.lnk")
$s.TargetPath = "cmd.exe"
$s.Arguments  = '/c "F:/ik_llama.cpp/run_ik_qwen38.bat"'
$s.WindowStyle = 7              # 7 = minimized
$s.IconLocation = "F:/ik_llama.cpp/personal/assets/ik_qwen_icon.ico"
$s.Description = "Qwen3.8 ik_llama.cpp server on :8080"
$s.Save()
```

After saving, the desktop icon shows the custom "Q" + lightning glyph. If the
icon does not appear, re-run the snippet (it overwrites the shortcut).

## Icon assets

- `personal/assets/ik_qwen_icon.ico` — 256×256 multi-res icon (dark violet
  rounded square, light "Q" with a teal lightning bolt, faint hybrid grid).
- `personal/assets/ik_qwen_ικ.png` — PNG preview of the same glyph.

Generated with Python/PIL on 2026-08-16.
