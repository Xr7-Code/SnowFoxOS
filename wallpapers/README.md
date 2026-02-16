# 🖼️ SnowFoxOS Wallpapers

Dieser Ordner enthält die SnowFox Wallpapers.

## 📦 Benötigte Dateien

Du musst folgende Dateien hier ablegen:

1. **snowfox_dark.png** - Dunkles Theme (Standard)
2. **snowfox_light.png** - Helles Theme (Optional)

## 🎨 Spezifikationen

- **Auflösung:** Mindestens 1920x1080
- **Format:** PNG
- **Design:** Zentrierter weißer Fuchs auf Gradient-Hintergrund
  - **Dark:** Dunkel-Lila → Dunkel-Orange
  - **Light:** Lila → Orange

## 🔧 Geblurrte Versionen erstellen

Nach dem Hinzufügen der Wallpapers, erstelle geblurrte Versionen für den Lockscreen:

```bash
cd ~/Pictures/wallpapers

# Dunkles Wallpaper blurren
convert snowfox_dark.png -blur 0x8 snowfox_dark_blur.png

# Helles Wallpaper blurren (optional)
convert snowfox_light.png -blur 0x8 snowfox_light_blur.png
```

## 📍 Dateien die du brauchst

```
~/Pictures/wallpapers/
├── snowfox_dark.png          # Haupt-Wallpaper
├── snowfox_dark_blur.png     # Für Lockscreen (auto-generiert)
├── snowfox_light.png          # Optional: Helles Theme
└── snowfox_light_blur.png     # Optional: Für Lockscreen (auto-generiert)
```

## 🎯 Wallpaper wechseln

1. **Via Settings:** `Mod+,` → Wallpaper wählen
2. **Manuell:** 
   ```bash
   swaymsg output "*" bg ~/Pictures/wallpapers/snowfox_dark.png fill
   ```

## 💡 Eigene Wallpapers

Du kannst auch eigene Wallpapers verwenden:

1. Füge dein Bild hier hinzu
2. Ändere in `~/.config/sway/config`:
   ```
   output * bg ~/Pictures/wallpapers/DEIN_BILD.png fill
   ```

---

**Hinweis:** Die Original-Wallpapers sind urheberrechtlich geschützt.
Für die Veröffentlichung eigener SnowFoxOS-Installationen benötigst du eigene Wallpapers.
