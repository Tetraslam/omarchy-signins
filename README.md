# Sign-ins for Omarchy

A quiet key in the bar while one of your command-line sign-ins has lapsed, and nothing at all otherwise.

It checks, without ever prompting:

- **Google Cloud**: your user login and application default credentials (both fixed by one `gcloud auth login --update-adc`)
- **GitHub CLI**
- **Tailscale**
- **OpenCode MCP servers** that need you to sign in

Each check only runs when its tool is installed and set up. Click the key for what's signed out and the command that fixes it; Enter runs it in a floating terminal and the widget checks again while you finish signing in.

Don't care about one? Press `i` on it. Ignored sign-ins stay listed (dimmed) but never bring the key back. Ignoring is saved in the widget's `ignored` setting.

## Install

```bash
omarchy plugin add https://github.com/tetraslam/omarchy-signins --enable
```

## Settings

| Key | Default | |
|---|---|---|
| `checkMinutes` | `10` | How often to check |
| `notify` | `false` | Also send a desktop notification when something lapses |
| `ignored` | `[]` | Check ids to ignore (managed with `i`) |

## License

MIT
