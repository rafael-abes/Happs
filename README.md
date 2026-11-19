# Happs

Happs is a SwiftUI iOS app for campus life. See which friends are on campus, create and join "Happs" (events), organise friends into groups, share photo recaps after an event, and describe an event in one sentence to have it drafted for you.

<!-- Add 3 or 4 screenshots here, for example: ![Happs list](docs/screenshots/happs-list.png) -->

## Features

- **Happs (events):** create, edit, cancel, join and leave, with a list view and a map view.
- **Friends and presence:** friend requests, search by name, and a live campus map showing friends who are on campus and visible. Invisible Mode hides you.
- **Groups:** friend groups with invitations and an activity feed.
- **Photo recaps (FOMO):** after a Happ ends, attendees can share up to 3 photos within 24 hours. People who did not attend see a blurred, locked teaser. Friends who missed it get a "see what you missed" notification.
- **Describe it (AI):** type or dictate a sentence and Google Gemini drafts the Happ. You review the draft before anything is saved. It asks for your explicit consent first.
- **Event suggestions:** pick a real event from the Ticketmaster Discovery API to start a Happ.
- **Voice:** dictation into text fields (speech to text) and read-aloud for Happs and notifications (text to speech).
- **Notifications:** in-app inbox, local banners, badge count, and local reminders to share photos after an event.
- **Safety and privacy:** on-device content filter, report (photos, Happs, groups, profiles), block people, in-app account deletion, and a Privacy and Safety screen.
- **Profile pictures:** choose a symbol or your own photo.
- **Accessibility:** VoiceOver labels, Dynamic Type, WCAG-checked colour contrast, Reduce Motion support, and automated accessibility audit tests.
- **Offline and onboarding:** offline overlay and a first-run welcome tour.

## Tech stack

| Area | Technology |
| --- | --- |
| UI | SwiftUI (UIKit types only where SwiftUI has no equivalent) |
| Auth | Firebase Authentication (email and password, Google Sign-In) |
| Database | Cloud Firestore (real-time snapshot listeners) |
| Security | Firebase App Check (debug provider in Debug, App Attest in Release) |
| AI | Firebase AI Logic with Google Gemini, Firebase Remote Config for the model name and a kill switch |
| Photo storage | Supabase Storage (private bucket, signed URLs) |
| Events | Ticketmaster Discovery API |
| Maps and location | MapKit, CoreLocation |
| Voice | Speech framework, AVFoundation |
| Tests | XCTest, `performAccessibilityAudit` |

## Architecture

- **Views** (`Views/`, `Components/`) draw state and forward actions. They do not talk to Firebase directly.
- **Stores and services** (`Services/`) are `ObservableObject` classes (`HappStore`, `FriendStore`, `GroupStore`, `ProfileStore`, `NotificationStore`, `RecapStore`, `SafetyStore`, `AuthService`). They own the Firestore listeners and writes and publish state with `@Published`. They are created once in `ContentView` and shared with `.environmentObject`.
- **Models** (`Models/`) are structs mapped to Firestore documents.
- **Pure helpers** (`ContentFilter`, `GroupMatcher`, `Geohash`, `RecapRules`, `RecapNotifications`, `AIConsent` and others) are stateless and unit tested.

Every Swift file starts with a CODE OVERVIEW comment explaining what it does and why.

## Project structure

```
Happs/
  HappsApp.swift          App entry, Firebase and App Check setup
  ContentView.swift       Root wiring of all stores and listeners
  Models/                 Data types (Happ, UserProfile, FriendGroup, Recaps, ...)
  Services/
    Stores/               Firestore-backed stores
    Misc/                 AuthService, NotificationWriter, NetworkMonitor, AppError
    Safety/               ContentFilter, SafetyStore, AccountDeletionService
    Recaps/               Image processing, Supabase storage, FOMO notifications and reminders
    VertexAI/             Gemini integration, consent, daily usage limiter
    STT_TTS/              Speech recognition and synthesis
  Views/                  Screens
  Components/             Reusable UI pieces and helpers
HappsTests/               Unit tests
HappsUITests/             Accessibility audit UI tests
```

## Getting started

### Requirements

- A Mac with a recent version of Xcode and an iOS 17 or later SDK
- A Firebase project with Authentication (Email and Google), Firestore, App Check, Firebase AI Logic (Gemini Developer API) and Remote Config enabled
- A Supabase project with a private storage bucket for recap photos
- A free Ticketmaster Discovery API key from developer.ticketmaster.com

### Setup

1. Clone the repository and open the project in Xcode. Let Swift Package Manager resolve the dependencies (Firebase, GoogleSignIn, Supabase Swift).
2. Download `GoogleService-Info.plist` from your Firebase project and add it to the Happs target. Without it the app shows a "Firebase Setup Required" screen.
3. Create `Happs/Secret.swift` (it is not committed, see `.gitignore`):

   ```swift
   enum Secrets {
       static let ticketmasterAPIKey = "YOUR_TICKETMASTER_KEY"
       static let supabaseURL = "YOUR_SUPABASE_PROJECT_URL"
       static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
   }
   ```

4. In Supabase, create the private recap bucket and add policies that let signed-in users upload and read according to the Firebase ID token (the app passes the Firebase ID token to Supabase as the access token).
5. Add the Firestore security rules and the collection-group index described in `SAFETY_AND_PRIVACY.md` (collection group `recaps`, field `authorID`).
6. On the first Debug run, copy the App Check debug token from the Xcode console and register it in the Firebase console under App Check.
7. Replace the placeholder contact details in `Services/Safety/SupportInfo.swift` with a real support email and privacy policy URL before any public release.
8. Build and run on a simulator or device.

### Running the tests

In Xcode choose Product > Test. This runs the unit tests (content filter, reports, consent, FOMO notifications, reminders, accessibility wording and contrast) and the accessibility audit UI tests.

## Privacy and safety

- Location is requested only while the app is in use. It is written to the database only while you are inside the campus area and visible, and is deleted when you leave or sign out.
- "Describe it" sends only the sentence you enter, today's date, your time zone and the category names to Google Gemini, and only after you give consent. You can withdraw consent in Me > Privacy and Safety.
- Recap photos are stored in a private bucket. People who did not attend see only a tiny blurred preview.
- You can delete your account and data inside the app.

See `SAFETY_AND_PRIVACY.md` for what is enforced in the app, what needs server rules, and known limits.

## Known limitations

- The content filter is a simple on-device word filter and is a first layer only.
- Blocking and the AI daily limit are enforced in the app and need Firestore rules and server checks for full protection.
- Notifications to other users use the in-app listener and local banners; there is no background push yet.
- Release builds need a paid Apple Developer account for App Attest.
- Sign in with Apple is not implemented yet.

## Acknowledgements

Firebase, Google Gemini, Supabase, Ticketmaster Discovery API, GoogleSignIn, Apple frameworks (SwiftUI, MapKit, CoreLocation, Speech, AVFoundation).
