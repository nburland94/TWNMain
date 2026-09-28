# Turning on "Sign in with Google / Apple" — Needed Tools

The app code is done (round 46). What's left is the one-time setup in three dashboards: **Supabase** (free), **Google Cloud** (free) and **Apple Developer** (needs the paid Apple Developer Program). Then paste two values into `Resources/account.json` and build again.

Until `account.json` is filled in, the app opens straight in with no sign-in screen, as it does now.

Allow about 45 minutes. Do Google first, since it's quicker. You can leave Apple until later: set `"providers": ["google"]` and only the Google button shows.

---

## 1. Supabase: the sign-in service

1. Go to **supabase.com**, sign up, and click **New project**. Name it `needed-tools`, choose a region near you, and save the database password somewhere safe. (The app doesn't use the database; the password is only needed for Supabase itself.)
2. When the project is ready, open **Project Settings → API** (on newer dashboards it's **API Keys**). Copy two things:
   - **Project URL**, which looks like `https://abcdefgh.supabase.co`. The `abcdefgh` part is your *project ref*.
   - The **anon / public** key. On newer dashboards it's the **publishable** key, starting `sb_publishable_`.
   - Don't copy the `service_role` or **secret** key. Neither of them ever goes in the app.
3. Open **Authentication → URL Configuration**:
   - **Site URL**: your website (for example `https://thiswasneeded.com`).
   - **Redirect URLs**: click **Add URL** and enter exactly `neededtools://auth-callback`, then save. This is how the sign-in window hands you back to the app.
4. Open **Authentication → Sign In / Providers** (older dashboards: **Providers**). You'll turn on Google and Apple here in the next steps. Each provider shows a **Callback URL**, which is `https://<your-ref>.supabase.co/auth/v1/callback`. You'll need it for Google and Apple.

## 2. Google

1. Go to **console.cloud.google.com** and create a project called `Needed Tools`.
2. Open **APIs & Services → OAuth consent screen**. Newer dashboards call it **Google Auth Platform**.
   - **Branding**: app name *Needed Tools*, your support email, and a logo if you like.
   - **Audience**: *External*. When you're ready for other people to sign in, click **Publish app**. (While it's in *Testing*, only the test users you list can sign in.)
   - **Data access / scopes**: leave the defaults (`email`, `profile`, `openid`).
3. Open **APIs & Services → Credentials → Create credentials → OAuth client ID**:
   - Application type: **Web application**. It says Web because Supabase does the sign-in on the app's behalf.
   - **Authorized redirect URIs**: paste the Supabase Callback URL from step 1.4.
   - Click **Create**, then copy the **Client ID** and **Client secret**.
4. In Supabase, under **Authentication → Sign In / Providers → Google**: turn it on, paste the Client ID and Client secret, and save.

## 3. Apple

You need the Apple Developer Program ($99 a year), which you'll also want later for notarising the app. Everything below is in **developer.apple.com → Account → Certificates, Identifiers & Profiles**.

1. **App ID.** Go to Identifiers, click **+**, choose **App IDs**, then **App**.
   - Bundle ID: `com.thiswasneeded.neededtools`. This is the app's own identifier from `Info.plist`.
   - Tick **Sign in with Apple**, then click Continue and Register.
2. **Services ID.** Go to Identifiers, click **+**, and choose **Services IDs**.
   - Identifier: `com.thiswasneeded.neededtools.signin`. It must be different from the App ID.
   - After registering it, open it, tick **Sign in with Apple**, and click **Configure**:
     - Primary App ID: the one from step 1.
     - **Domains**: `<your-ref>.supabase.co`, with no `https://`.
     - **Return URLs**: the Supabase Callback URL, `https://<your-ref>.supabase.co/auth/v1/callback`.
   - Save, then Continue and Save again.
3. **Key.** Go to **Keys**, click **+**, and name it `Needed Tools sign-in`.
   - Tick **Sign in with Apple**, click Configure, and choose the App ID. Then Register.
   - **Download the `.p8` file.** Apple only lets you download it once, so keep it safe and never put it in the app.
   - Note the **Key ID**. Your **Team ID** is shown at the top right of the developer site.
4. **The secret for Supabase.** Apple doesn't give you a fixed secret. Instead, you make one from the `.p8` file, and it lasts at most **6 months**.
   - In Supabase, open **Authentication → Sign In / Providers → Apple**. Its help text links to Supabase's own secret generator in their docs.
   - Give the generator your Team ID, Key ID, Services ID and the `.p8` file's contents.
   - Paste the result into **Secret Key**. Under **Client IDs**, put the Services ID (`com.thiswasneeded.neededtools.signin`). Turn Apple on and save.
   - Set a calendar reminder for 5 months from now to make a new secret the same way. If it expires, Apple sign-in stops working (Google keeps working).

## 4. Put it in the app

Open `Resources/account.json` and fill in the two values:

```json
{
  "supabaseUrl": "https://abcdefgh.supabase.co",
  "supabaseAnonKey": "eyJ…  (or sb_publishable_…)",
  "providers": ["apple", "google"]
}
```

Then run **Build-Needed-Tools.command** again. The anon/publishable key is designed to be public, so it's safe inside the app.

## 5. Try it

1. Open the app. The sign-in screen shows **Continue with Apple** and **Continue with Google**.
2. Click one. The Mac's secure sign-in window opens Google's or Apple's page. Sign in, and you're taken into the app.
3. Open your account (top left) → **Signed in**. It shows the email.
4. In **Pay**, create an invoice and click **Send**. The *From* line is your sign-in email.
   - With no app password saved, **Open in Mail** makes a new message in Mail with the PDF attached.
   - To send in one press from inside Pay, add the app password in Pay → Settings.

## What the app keeps, and where

- The session stays on this Mac at `~/Library/Application Support/NeededTools/account.json`, readable only by you. It isn't in the Keychain, so there are no pop-ups.
- The app only ever sees your name and email. Google or Apple handle the password, and your projects never leave your Mac.
- **Apple's "Hide my email"**: when someone chooses it, Apple gives a relay address (`…@privaterelay.appleid.com`). The app won't use it as the sending address. The account panel explains this and asks for the address they send from.
- **Signing out** (account panel → Sign out) ends the session and shows the sign-in screen again.
- If you're offline, you stay signed in. You're only signed out if Supabase refuses the session, for example because it was revoked.

## Next: licences

Sign-in says *who* someone is, and the licence (Lemon Squeezy) says whether they've *paid*. The next step is linking the two. The checkout would already know their email, and a subscription would follow the account to a new Mac.
