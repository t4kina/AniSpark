<div align="center">

<img src="assets/logo.jpg" width="100" style="border-radius: 22px"/>

# AniSpark

**Your personal anime & manga tracker, powered by AniList.**

[![Flutter](https://img.shields.io/badge/Flutter-3.41-02A9FF?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![AniList](https://img.shields.io/badge/AniList-API-02A9FF?style=flat-square)](https://anilist.co)
[![iOS](https://img.shields.io/badge/iOS-sideload-black?style=flat-square&logo=apple)](https://github.com/t4kina/AniSpark)

</div>

---

## ✨ Features

- 📺 **Track anime & manga** — synced with your AniList account in real time
- 🔔 **Episode alerts** — get notified when a new episode of your current anime airs
- 🌍 **Discover** — trending, seasonal, upcoming and top-rated content at a glance
- 📰 **Activity feed** — see what the people you follow are watching and reading
- 👤 **User profiles** — browse anyone's list, favourites and stats
- 🌓 **Light & dark mode** — full support for both themes
- 🌐 **Multilingual** — English, Spanish, Japanese, French, German, Portuguese, Italian and Korean

---

## 📱 Screenshots

### Dark mode

<div align="center">
<table>
  <tr>
    <td align="center"><img src="screenshots/dark_discover.jpg" width="180"/><br/><sub>Discover</sub></td>
    <td align="center"><img src="screenshots/dark_anime.jpg" width="180"/><br/><sub>Anime List</sub></td>
    <td align="center"><img src="screenshots/dark_manga.jpg" width="180"/><br/><sub>Manga List</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/dark_detail.jpg" width="180"/><br/><sub>Detail View</sub></td>
    <td align="center"><img src="screenshots/dark_feed.jpg" width="180"/><br/><sub>Activity Feed</sub></td>
    <td align="center"><img src="screenshots/dark_profile.jpg" width="180"/><br/><sub>Profile</sub></td>
  </tr>
</table>
</div>

### Light mode

<div align="center">
<table>
  <tr>
    <td align="center"><img src="screenshots/light_discover.jpg" width="180"/><br/><sub>Discover</sub></td>
    <td align="center"><img src="screenshots/light_anime.jpg" width="180"/><br/><sub>Anime List</sub></td>
    <td align="center"><img src="screenshots/light_manga.jpg" width="180"/><br/><sub>Manga List</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="screenshots/light_detail.jpg" width="180"/><br/><sub>Detail View</sub></td>
    <td align="center"><img src="screenshots/light_feed.jpg" width="180"/><br/><sub>Activity Feed</sub></td>
    <td align="center"><img src="screenshots/light_profile.jpg" width="180"/><br/><sub>Profile</sub></td>
  </tr>
</table>
</div>

---

## 🛠 Tech Stack

| | |
|---|---|
| **Framework** | Flutter 3.41 (Dart) |
| **API** | AniList GraphQL |
| **Auth** | OAuth 2.0 — Authorization Code (mobile) / Implicit (web) |
| **Storage** | Hive (local), SharedPreferences |
| **State** | Provider |
| **Notifications** | flutter\_local\_notifications |
| **Image cache** | cached\_network\_image |

---

## 📲 Install on iOS (Sideload)

> Requires [Sideloadly](https://sideloadly.io/) and a free Apple ID.

1. Download the latest `.ipa` from [Releases](https://github.com/t4kina/AniSpark/releases)
2. Open Sideloadly, drag the `.ipa` and connect your iPhone
3. Enter your Apple ID and hit **Start**
4. On your iPhone: **Settings → General → VPN & Device Management** → trust the certificate
5. Open AniSpark and log in with your AniList account

---

## 🔗 Connect with AniList

AniSpark uses your AniList account to sync your lists, track progress and send episode notifications. Log in from the Profile tab — no separate account needed.

---

<div align="center">

Made with ❤️ and Flutter &nbsp;·&nbsp; Data provided by [AniList](https://anilist.co)

</div>
