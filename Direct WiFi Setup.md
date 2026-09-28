# Needed Tools — Direct Wi-Fi transfer

This update sends images and clips directly from a Safari page on your iPhone to Needed Tools on your Mac. Photos and iCloud are not in the transfer path. No website deployment, cloud service or API subscription is needed for this mode.

## Set up once

1. Quit your existing Needed Tools app.
2. Unzip **NeededTools Direct WiFi.zip**. Put **Needed Tools.app** in your Applications folder, replacing your previous copy. Open this updated app. Your existing vault stays in its current folder; choose that same vault if asked.
3. Keep your Mac awake with Needed Tools open. Connect your iPhone and Mac to the same trusted Wi-Fi/local network. Avoid a guest network that isolates devices.
4. In Needed Tools, open **Home → Your phone**. Switch on **Direct Wi-Fi transfer**. Allow incoming connections/local network access if macOS asks.
5. Scan the displayed QR code with the iPhone Camera and open the link in **Safari**. This is the Mac’s local address, ending in `/capture/`, not thiswasneeded.info.
6. Bookmark that Safari page. Keep using the same address and browser so its saved queue remains accessible. Use Safari for the initial test; this local page is not an offline-installed website app.

## Send your first image

1. On the direct page, choose a project.
2. Tap **Photos** to select an image already on your phone, or use its capture button. Add any tags and tap **Keep**.
3. Tap **Send to Mac**. Keep Safari in the foreground until the message says **received by Mac**.
4. Open that project in the Mac Vault and check the image. It is filed automatically; you do not need to press Sync on the Mac.

Small images should transfer promptly once connected. Large clips depend on their size and Wi-Fi speed; there is no guaranteed transfer time.

## If a transfer stops

The direct page saves the original and retry intent before sending. Restore the connection and tap **Retry**, or reopen the same page while the Mac is reachable. It also attempts to resume a queued batch when the page reconnects or returns to the foreground. Retry uses the same item ID so a lost confirmation does not normally create another copy.

Keep the Mac awake, Needed Tools open and Safari in the foreground. If the page cannot connect, check the Direct Wi-Fi toggle and allow the app through the Mac firewall. The Mac’s **Use the Mac’s number instead** button provides an alternate address when its name cannot be resolved. Pick a working address before building a queue: different hostnames/IP addresses have separate browser storage. If you already queued files at one address, return to that address to access them.

Do not clear Safari website data while anything is pending. The app does not automatically delete originals after sending; **Clear confirmed** is a separate action for items the Mac acknowledged. Changing projects/tags after receipt edits the phone’s copy only.

## Images already in the old website Vault

The website Vault and this direct page have separate phone storage. Your old saved items are not automatically moved into this new page. Do not delete or reset the old website Vault.

For those items, use the old Vault’s **Sync** or its menu’s resend option and choose **AirDrop → your Mac**. Accept the files into Downloads, then press **Sync** in Needed Tools on the Mac. This bypasses Photos/iCloud and preserves project/tag information carried by the old Vault’s named files. If an old item is unavailable to resend because its original was already removed, recover it from Photos or an existing copy; the update cannot reconstruct missing original bytes.

For new captures near your Mac, use the new Direct Wi-Fi page. For collecting away from the Mac, the existing website Vault remains separate. The direct page needs the Mac to be reachable to load; it does not provide anywhere-in-the-world or background iPhone syncing.

## What was verified

- Apple Silicon and Intel builds completed; the combined app signature was verified.
- Client checks passed for project/tag/original transfer, confirmation matching, invalid credentials, interruption, partial batches, retry IDs and phone-storage failure.
- Native receiver tests passed for file/tag persistence, duplicate retries, invalid IDs/formats and index-write failure recovery.
- The bundled phone page’s script paths and asset links were checked.
- The previous Sort, Design, dark-mode and template fixes are included. The C template mockups are not implemented.

A real iPhone-to-Mac transfer has not been tested here. Start with one image using the steps above, then send a larger batch once it appears in your Vault.
