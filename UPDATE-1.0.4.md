# Needed Tools 1.0.4 — owner and licence-key beta

- Sort recognises additional video/audio containers plus media types registered with macOS. MXF was already recognised; it remains supported for sorting. No transcoding is performed. Thumbnails still depend on macOS/camera decoders; this is not a promise of preview support for every codec.
- Video/audio have separate scene sections and separate destination folders, even when a custom structure omits Audio or shares its folder with Footage.
- Copy & Sort remains the default. Move & Sort asks before proceeding, copies and verifies every file, saves the manifest and Premiere export, then rechecks each source against its destination before removing the original. Failed copying/cancellation before cleanup retains all originals. Cancellation during cleanup retains the remaining originals and reports how many were removed. Temporary space for the verified copy is needed, even on the same drive.
- Scene labels export to a JSON manifest and an ExtendScript import script. The script creates separate scene/video/audio bins and uses Adobe's clip-label API. Requires an ExtendScript-compatible Premiere script runner. It does not run via File > Import, automatically update existing timeline clips, or include a UXP panel. See the generated readme. Custom Premiere label preferences affect displayed colours. Automated API mocks pass; live Premiere verification remains outstanding.
- Shots reference sizing reaches 25%; text stays readable and column headings sit below the logo.
- Grab and Vault choose GIF or MP4 first and show only that format's options. Existing per-format settings remain intact.
- Home's orange outline stays inside each photo and is explicitly displayed on hover/focus.
- Browser grabs use copied image bytes immediately; support delayed clipboard reads, more formats and Safari archives. URL-only imports parse supplied sources and have bounded cancellable downloads.

## Validation

Universal Apple Silicon/Intel build; Swift typecheck; JavaScript syntax; application signature checks; signed feed hash/signature verified against the existing beta public key.

Temporary-file copy/move regression checks cover byte verification, existing-file collision protection, cancellation, and changed originals. Premiere API mock checks cover separate bins and labels 0/9. Clipboard parsing/image fixtures and successful/404/stalled URL downloads pass. Native clipboard smoke checks skip when the sandbox cannot reach the pasteboard service. Exact Pinterest reproduction and visual checks in the running application remain to be tested.

Beta continues using licence keys and does not include the owner's local email OAuth configuration.
