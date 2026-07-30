# Windows build

The Windows edition is a small Windows 10/11 x64 system-tray app. It reads the
same shared Cloudflare feed as the macOS edition, so installed Windows clients
do not make additional TwitterAPI.io requests.

## Build

```powershell
dotnet publish .\Windows\TiboWeLoveYou.Windows.csproj `
  --configuration Release `
  --runtime win-x64 `
  --self-contained true `
  --output .\dist\windows
```

The official ZIP is built on GitHub's Windows runner.
