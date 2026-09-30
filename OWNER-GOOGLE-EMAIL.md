# Personal build: Google sign-in and email

Google uses the existing desktop OAuth client with PKCE and a loopback callback. One consent grants identity (openid/email/profile) and gmail.send. Pay and Project use that same account; no SMTP app password is needed. Apple account sign-in remains on Supabase. This Google session is local to the Mac; it does not create or link a Supabase account or a billing subscription.

Only licence provider `off` enables this connection. Beta files and published update feeds were not changed. Do not run Publish-Update.command to install this personal change.

Copy email-oauth.example.json to email-oauth.json and supply the desktop OAuth configuration locally before building. The real configuration is ignored by Git. Enable the Gmail API and include the Google account among test users while Google consent is in Testing. Testing refresh tokens with Gmail scopes expire after seven days, so reconnect when prompted.

Existing Google users: in Pay Settings choose Sign in with Google once to grant sending permission. Fresh users can Continue with Google at launch. The same saved connection is used by Project. Send me a test sends only when clicked. Sign out clears the personal email connection. Apple Mail remains an explicit draft fallback; a draft is never marked as sent.

Validation: universal Apple Silicon/Intel build, JavaScript parse checks, local MIME/recipient/attachment tests. A fresh interactive Google consent and real delivery must still be checked in the installed owner build.
