# Tronbyt apps

My custom apps for a Tronbyt server. The server reads apps from this layout:

```
apps/<app-folder>/<app>.star      # the app (required)
apps/<app-folder>/manifest.yaml   # name, summary, category (optional)
apps/<app-folder>/<app>.webp      # preview image shown in the app list (optional)
```

The folder name becomes the app's ID on the server.

## Workflow

```bash
pixlet serve apps/simpleclock/simple_clock.star     # live preview at http://localhost:8080
pixlet check apps/simpleclock/simple_clock.star     # lint + manifest check
pixlet render apps/simpleclock/simple_clock.star -o apps/simpleclock/simple_clock.webp   # refresh preview
```

Push to GitHub, then refresh the custom apps repo in the Tronbyt web UI to pick up changes.
