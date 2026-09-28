# Brief: set up "Continue with Google" for Needed Tools (Supabase + Google Cloud)

**Goal:** turn on Google sign-in for the Needed Tools Mac app. The app code is already built. It needs a Supabase project with Google sign-in switched on, plus two values put into the app's settings file. **Google only for now. Skip Apple**, because it needs the paid Apple Developer Program, which Nathan hasn't joined yet.

Nathan signs up and logs in to each site himself. Pause and ask him whenever a page wants a password, a verification code, 2-step approval or payment.

## Part 1: Supabase (free plan)

1. Go to **supabase.com**, sign in (Nathan can use "Continue with GitHub"), and click **New project**.
   - Name: `needed-tools`. Region: the one nearest Nathan. Plan: **Free**.
   - Database password: generate one and have Nathan save it in his password manager. The app doesn't use it.
2. Wait until the project has finished setting up. Then open **Project Settings → API**. On newer dashboards it's **API Keys**. Note two values:
   - **Project URL**, like `https://abcdefgh.supabase.co`.
   - The **anon / public** key. On newer dashboards it's the **publishable** key, starting `sb_publishable_`.
   - Never copy the `service_role` or **secret** key anywhere.
3. Open **Authentication → URL Configuration**:
   - **Site URL:** `https://thiswasneeded.info`.
   - **Redirect URLs:** click **Add URL** and enter exactly `neededtools://auth-callback`. Then save.
4. Open **Authentication → Sign In / Providers → Google**. Don't turn it on yet. Copy the **Callback URL** shown there; it looks like `https://abcdefgh.supabase.co/auth/v1/callback`. Part 2 needs it.

## Part 2: Google Cloud (free)

1. Go to **console.cloud.google.com**. Create a new project named `Needed Tools` and select it.
2. Open **APIs & Services → OAuth consent screen**. Newer dashboards call it **Google Auth Platform**, and it may ask you to click **Get started** first.
   - App name: `Needed Tools`. User support email and developer contact: Nathan's email.
   - App home page: `https://thiswasneeded.info`. Privacy policy: `https://thiswasneeded.info/privacy.html`. Authorised domain: `thiswasneeded.info`.
   - Audience: **External**.
   - Scopes: leave the defaults (email, profile, openid). Don't add any sensitive scopes.
   - Save. Then under **Audience**, click **Publish app** so anyone can sign in, not only listed test users.
3. Open **APIs & Services → Credentials → Create credentials → OAuth client ID**.
   - Application type: **Web application**. Name: `Needed Tools (Supabase)`.
   - **Authorized redirect URIs:** paste the Supabase Callback URL from Part 1, step 4.
   - Leave Authorized JavaScript origins empty. Click **Create**.
   - Copy the **Client ID** and **Client secret**.

## Part 3: Connect them

1. Back in Supabase, open **Authentication → Sign In / Providers → Google**.
   - Turn **Enable** on.
   - Paste the Client ID and Client secret.
   - Save.
2. The Google Client secret stays in Supabase only. Don't paste it into files or chats.

## Part 4: Put the values in the app

1. On Nathan's Mac, find the Needed Tools source folder: the unzipped build kit, likely `~/NeededBuild/NeededTools`. It's the folder with `Build-Needed-Tools.command` in it.
2. Open `Resources/account.json` and set:
   ```json
   {
     "_help": "(leave as is)",
     "supabaseUrl": "https://abcdefgh.supabase.co",
     "supabaseAnonKey": "<the anon / publishable key>",
     "providers": ["google"]
   }
   ```
   `providers` is **only** `["google"]` for now.
3. Double-click **Build-Needed-Tools.command** to rebuild. Then open the new app. The sign-in screen should show **Continue with Google**.
4. Test it: click it and sign in with Google. The app should open. Check that the account panel (logo, top left) shows **Signed in · With Google** and the email.

## Report back to Nathan

- ✅ or ❌ for each part.
- The Supabase **Project URL** and **anon/publishable key**. These are fine to share; they're public by design. Don't include the database password, the service or secret key, or the Google Client secret.
- Anything that didn't match these steps, with a screenshot.

## If something goes wrong

- **"redirect_uri_mismatch" from Google:** the Authorized redirect URI in Google must match the Supabase Callback URL exactly.
- **The sign-in window finishes but the app doesn't open:** check that `neededtools://auth-callback` is in Supabase's Redirect URLs.
- **"Access blocked: app not verified" or only some people can sign in:** the consent screen is still in Testing. Click Publish app.
