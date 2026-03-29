# Screenshots for email instructions

Screenshots are embedded as inline images in the proxy email via Google Drive.

## Steps

1. Take screenshots of the Telegram app (5 steps):
   - `step1.png` — Shield icon in top-right corner / Settings > Data and Storage > Proxy
   - `step2.png` — "Add Proxy" button (also shows the "Use Proxy" toggle)
   - `step3.png` — Select MTPROTO protocol
   - `step4.png` — Enter server, port, and secret key
   - `step5.png` — "Use Proxy" toggle enabled

2. Upload each PNG to Google Drive (any folder)

3. For each uploaded file, right-click > "Get link" > copy the file ID from the URL:
   ```
   https://drive.google.com/file/d/THIS_IS_THE_FILE_ID/view
   ```

4. Paste the file IDs into `SCREENSHOT_IDS` in `Code.gs`:
   ```javascript
   const SCREENSHOT_IDS = {
     step1: "1AbCdEfGhIjKlMnOpQrStUvWxYz",
     step2: "...",
     step3: "...",
     step4: "...",
     step5: "...",
   };
   ```

5. Make sure the Google Drive files are accessible to the script (same Google account, or shared).

6. Run `testSendEmail()` in the Apps Script editor to verify.

## Image recommendations

- PNG format, ~300-400px wide
- Crop to relevant area (not full screen)
- Highlight the button/toggle being described (optional red circle/arrow)
