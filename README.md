
# 🧠 AI Coach — Democratizing Personal & Career Coaching

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![RevenueCat](https://img.shields.io/badge/RevenueCat-In--App%20Purchases-E75243)](https://www.revenuecat.com)
[![Google Play](https://img.shields.io/badge/Google%20Play-Live-brightgreen)](https://play.google.com/store/apps/details?id=com.portablecook.aicoach)

> **Official Store Listing**: [Download on Google Play](https://play.google.com/store/apps/details?id=com.portablecook.aicoach)  
> **Built for RevenueCat Shipaton 2026** | Targeting: **Influencer Award — Career Coaching (Leadership Heather)** & **HAMM Award**

---

## 📌 Overview
Executive coaching is typically locked behind thousands of dollars in fees. **AI Coach** democratizes mentorship by enabling users, professionals, and new managers to build personalized advisors and roleplay high-stakes workplace conversations safely before the stakes are real.

---

## 🚀 Key Features
* **Personal Context Engine**: Define your personal values, workplace role, and communication hurdles for fully personalized coaching.
* **Custom Coach Creation Studio**: Build specialized mentors (boundary setting, salary negotiation, executive presence) with tailored system prompts.
* **Real-Time Roleplay Simulations**: Practice delivering critical feedback and saying no with instant AI feedback.
* **Coach Marketplace**: Discover and share coaches with one-tap deep links.
* **Hybrid Monetization via RevenueCat**: Pro ($25/mo) and Premium ($35/mo) plans paired with consumable coaching session packs.

---

## 💳 Judge Reviewer Credentials & Promo Codes
* **Reviewer Account**: `reviewer@aicoach.app` / `Reviewer123!`
* **Google Play / RevenueCat Promo Codes**:
  * 👑 **Premium Subscription**: `AICOACHFREE`
  * ⚡ **10 Coaching Credit Pack**: `67FA4Z864PXTV3E16PSHTL1`

---

## 🛠 Tech Stack & Architecture
* **Frontend**: Flutter / Dart with Material 3 styling
* **Monetization Engine**: RevenueCat SDK (`purchases_flutter`)
* **Backend API**: Python REST API hosted on Azure App Services (`https://aico-dwd4bddyggaygrgg.eastus-01.azurewebsites.net`)
* **LLM Engine**: Google Gemini 3 Flash conversational pipelines

---

## 📂 Project Structure
```text
aicoach/
├── android/               # Android native configuration
├── ios/                   # iOS configuration
├── lib/
│   ├── main.dart          # Main application, models, routing, RevenueCat initialization
│   ├── models/            # Coach, Message, UserSession, UserTier
│   ├── services/          # ApiService (Azure auth, coach creation, chat endpoints)
│   └── screens/           # DiscoverScreen, MyCoachesScreen, ContextScreen, ChatScreen, UpgradeScreen
├── azure_aico/            # Azure cloud backend
│   ├── app.py             # Flask REST endpoints
│   ├── aicoach.db         # SQLite database
│   └── requirements.txt   # Python dependencies
└── pubspec.yaml           # Flutter dependencies
```

---

## ⚙️ Getting Started
```bash
git clone https://github.com/Jerryblessed/aicoach.git
cd aicoach
flutter pub get
flutter run
```

---

## 📄 License
This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
