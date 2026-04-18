# ATV-deJunker

Bash script to debloat Android TV devices. Replaces the stock Google TV launcher with AT4K, removes preloaded bloatware, installs streaming apps, and disables sponsored content.

## Usage

```bash
chmod +x dejunk-android-tv.sh
./dejunk-android-tv.sh
```

Requires ADB over WiFi. The script prompts for the TV's IP address and walks through each step.

## What it does

1. Connects to the TV via ADB over WiFi
2. Installs streaming apps (Netflix, Prime Video, Apple TV, YouTube, Plex, Disney+)
3. Installs AT4K launcher and sets it as default
4. Disables the stock Google TV launcher
5. Removes bloatware (recommendation ads, Play Games, YouTube Music, regional preloads)
6. Disables home panel sponsored content
7. Reboots into the clean launcher

## Recovery

```bash
adb shell pm install-existing com.google.android.tvlauncher
adb shell pm enable com.google.android.tvlauncher
```

## Tested on

Prism+ Android TV 10

## License

MIT
