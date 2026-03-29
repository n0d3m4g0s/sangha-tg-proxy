/**
 * Sangha TG Proxy — Google Apps Script
 *
 * Automates user registration:
 * 1. User fills Google Form (email, TG username/phone, code word)
 * 2. Script validates code word
 * 3. Calls webhook API to create proxy credentials
 * 4. Emails user their personal proxy link
 * 5. Updates Google Sheet with status
 */

const CONFIG = {
  API_URL: "https://YOUR_DUTCH_VM_HOST",  // e.g. https://nl.rigpa.space
  API_KEY: "CHANGEME",  // Same as SANGHA_API_KEY in .env
  CODE_WORD: "ригпа",
  ADMIN_EMAIL: "admin@example.com",  // Change to actual admin email
};

/**
 * Google Drive file IDs for inline screenshots in the email.
 * Leave empty to send emails without screenshots.
 * To add screenshots: upload PNG to Google Drive, copy file ID, paste here.
 */
const SCREENSHOT_IDS = {
  step1: "",  // Иконка щита / настройки прокси
  step2: "",  // Кнопка «Добавить прокси»
  step3: "",  // Выбор протокола MTPROTO
  step4: "",  // Ввод сервера, порта, ключа
  step5: "",  // Тумблер «Использовать прокси»
};

/**
 * Columns in the Google Sheet (1-indexed).
 * Adjust if your form has different column order.
 */
const COL = {
  TIMESTAMP: 1,
  EMAIL: 2,
  USERNAME_OR_PHONE: 3,
  CODE_WORD: 4,
  SECRET: 5,
  LINK: 6,
  STATUS: 7,
  ACTIVATED: 8,
};

/**
 * Trigger: runs automatically when a form response is submitted.
 * Install via: createTrigger() or manually in Apps Script triggers UI.
 */
function onFormSubmit(e) {
  var sheet = SpreadsheetApp.getActiveSpreadsheet().getActiveSheet();
  var row = e.range.getRow();

  try {
    var email = sheet.getRange(row, COL.EMAIL).getValue().toString().trim();
    var usernameOrPhone = sheet.getRange(row, COL.USERNAME_OR_PHONE).getValue().toString().trim();
    var codeWord = sheet.getRange(row, COL.CODE_WORD).getValue().toString().trim().toLowerCase();

    // Validate code word
    if (codeWord !== CONFIG.CODE_WORD) {
      sheet.getRange(row, COL.STATUS).setValue("REJECTED: wrong code word");
      return;
    }

    // Validate email
    if (!email || !email.includes("@")) {
      sheet.getRange(row, COL.STATUS).setValue("REJECTED: invalid email");
      return;
    }

    // Sanitize username: strip @, keep alphanumeric + underscore
    // For phone: keep only digits
    var username = sanitizeUsername(usernameOrPhone);
    if (!username) {
      sheet.getRange(row, COL.STATUS).setValue("REJECTED: invalid username/phone");
      return;
    }

    // Call webhook API
    var result = addUser(username);

    // Update sheet
    sheet.getRange(row, COL.SECRET).setValue(result.secret);
    sheet.getRange(row, COL.LINK).setValue(result.tme_link);
    sheet.getRange(row, COL.STATUS).setValue(result.existed ? "ACTIVE (existed)" : "ACTIVE");
    sheet.getRange(row, COL.ACTIVATED).setValue(new Date());

    // Send email with proxy link
    sendProxyEmail(email, username, result.tme_link, result.tg_link);

  } catch (error) {
    sheet.getRange(row, COL.STATUS).setValue("ERROR: " + error.message);
    // Notify admin
    try {
      GmailApp.sendEmail(
        CONFIG.ADMIN_EMAIL,
        "Sangha Proxy Error",
        "Error processing row " + row + ": " + error.message + "\n\nStack: " + error.stack
      );
    } catch (mailErr) {
      // Can't even email admin, just log
      Logger.log("Failed to notify admin: " + mailErr.message);
    }
  }
}

/**
 * Sanitize Telegram username or phone number.
 * Username: strip @, keep [a-zA-Z0-9_], min 3 chars
 * Phone: keep digits only, must start with 7 and be 11 digits
 */
function sanitizeUsername(input) {
  input = input.trim();

  // Check if it looks like a phone number
  var digitsOnly = input.replace(/\D/g, "");
  if (digitsOnly.length >= 10) {
    // Normalize Russian phone: +7, 8, or 7 prefix
    if (digitsOnly.startsWith("8") && digitsOnly.length === 11) {
      digitsOnly = "7" + digitsOnly.substring(1);
    }
    if (digitsOnly.length === 10) {
      digitsOnly = "7" + digitsOnly;
    }
    if (digitsOnly.length === 11 && digitsOnly.startsWith("7")) {
      return digitsOnly;
    }
  }

  // Treat as username
  var username = input.replace(/^@/, "").replace(/[^a-zA-Z0-9_]/g, "");
  if (username.length >= 3) {
    return username;
  }

  return null;
}

/**
 * Call webhook API to add a user.
 */
function addUser(username) {
  var response = UrlFetchApp.fetch(CONFIG.API_URL + "/api/add-user", {
    method: "post",
    contentType: "application/json",
    headers: {"X-API-Key": CONFIG.API_KEY},
    payload: JSON.stringify({username: username}),
    muteHttpExceptions: true,
  });

  var code = response.getResponseCode();
  if (code !== 200) {
    throw new Error("API returned " + code + ": " + response.getContentText());
  }

  return JSON.parse(response.getContentText());
}

/**
 * Extract server, port, secret from tme link URL.
 */
function parseProxyUrl(tmeLink) {
  var queryString = tmeLink.split("?")[1] || "";
  var params = {};
  queryString.split("&").forEach(function(pair) {
    var kv = pair.split("=");
    params[kv[0]] = decodeURIComponent(kv[1] || "");
  });
  return {
    server: params.server || "",
    port: params.port || "",
    secret: params.secret || ""
  };
}

/**
 * Build HTML email body.
 */
function buildProxyEmailHtml(tmeLink, credentials, screenshotKeys) {
  var hasScreenshots = screenshotKeys.length > 0;

  var html = '<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="margin:0;padding:0;background-color:#f5f5f5;">' +
    '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5f5;">' +
    '<tr><td align="center" style="padding:20px 10px;">' +
    '<table role="presentation" width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background-color:#ffffff;border-radius:8px;overflow:hidden;">';

  // --- Header ---
  html += '<tr><td style="padding:30px 30px 20px 30px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:16px;line-height:1.6;color:#333333;">';

  // Greeting
  html += '<p style="margin:0 0 16px 0;">Здравствуйте!</p>';
  html += '<p style="margin:0 0 16px 0;">Ваша персональная ссылка готова. Откройте её на телефоне — приложение предложит подключиться:</p>';

  // Button
  html += '<p style="margin:0 0 24px 0;text-align:center;">' +
    '<a href="' + tmeLink + '" style="display:inline-block;padding:14px 32px;background-color:#4A90D9;color:#ffffff;text-decoration:none;border-radius:6px;font-size:16px;font-weight:600;">Подключиться</a>' +
    '</p>';

  // Warning
  html += '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px 0;">' +
    '<tr><td style="padding:14px 18px;background-color:#fff8e1;border-left:4px solid #f5a623;border-radius:0 4px 4px 0;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;line-height:1.5;color:#5d4e37;">' +
    '<strong>Обратите внимание:</strong> ссылка персональная и предназначена только для вашего использования. ' +
    'Если по ней будет обнаружена подозрительно высокая активность (что может означать передачу ссылки третьим лицам), ' +
    'она будет заблокирована без предупреждения. В случае блокировки вы можете обратиться к администратору.' +
    '</td></tr></table>';

  // --- Credentials table ---
  html += '<p style="margin:0 0 12px 0;font-size:15px;color:#555555;">Если автоматическое подключение не сработало, настройте вручную. Данные для ввода:</p>';

  html += '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px 0;border:1px solid #e0e0e0;border-radius:6px;overflow:hidden;">' +
    '<tr style="background-color:#f7f7f7;">' +
    '<td style="padding:10px 14px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;font-weight:600;color:#555;border-bottom:1px solid #e0e0e0;width:100px;">Сервер</td>' +
    '<td style="padding:10px 14px;font-family:\'Courier New\',Courier,monospace;font-size:14px;color:#333;border-bottom:1px solid #e0e0e0;word-break:break-all;">' + credentials.server + '</td>' +
    '</tr>' +
    '<tr>' +
    '<td style="padding:10px 14px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;font-weight:600;color:#555;border-bottom:1px solid #e0e0e0;">Порт</td>' +
    '<td style="padding:10px 14px;font-family:\'Courier New\',Courier,monospace;font-size:14px;color:#333;border-bottom:1px solid #e0e0e0;">' + credentials.port + '</td>' +
    '</tr>' +
    '<tr style="background-color:#f7f7f7;">' +
    '<td style="padding:10px 14px;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;font-weight:600;color:#555;">Ключ</td>' +
    '<td style="padding:10px 14px;font-family:\'Courier New\',Courier,monospace;font-size:13px;color:#333;word-break:break-all;">' + credentials.secret + '</td>' +
    '</tr>' +
    '</table>';

  // --- Manual setup instructions ---
  html += '<p style="margin:0 0 12px 0;font-size:15px;font-weight:600;color:#333;">Пошаговая настройка вручную:</p>';

  var steps = [
    {
      key: "step1",
      text: 'Нажмите на иконку щита в правом верхнем углу приложения. Также можно найти в настройках: <em>Настройки → Данные и память → Прокси</em>.',
      alt: "Шаг 1: иконка щита"
    },
    {
      key: "step2",
      text: 'Нажмите <strong>«Добавить прокси»</strong>.',
      alt: "Шаг 2: добавить прокси"
    },
    {
      key: "step3",
      text: 'Выберите протокол <strong>MTPROTO</strong>.',
      alt: "Шаг 3: выбор MTPROTO"
    },
    {
      key: "step4",
      text: 'Введите <strong>сервер</strong>, <strong>порт</strong> и <strong>ключ</strong> из таблицы выше.',
      alt: "Шаг 4: ввод данных"
    },
    {
      key: "step5",
      text: 'Если подключение не активировалось автоматически, включите переключатель <strong>«Использовать прокси»</strong>.',
      alt: "Шаг 5: включить прокси"
    }
  ];

  for (var i = 0; i < steps.length; i++) {
    var step = steps[i];
    var num = i + 1;
    html += '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 12px 0;">' +
      '<tr><td style="vertical-align:top;width:28px;padding:0 8px 0 0;">' +
      '<span style="display:inline-block;width:24px;height:24px;line-height:24px;text-align:center;background-color:#4A90D9;color:#fff;border-radius:50%;font-size:13px;font-weight:600;">' + num + '</span>' +
      '</td><td style="font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;line-height:1.5;color:#333;vertical-align:top;padding-top:2px;">' +
      step.text;

    // Screenshot if available
    if (hasScreenshots && screenshotKeys.indexOf(step.key) !== -1) {
      html += '<br><img src="cid:' + step.key + '" alt="' + step.alt + '" style="max-width:100%;height:auto;margin:8px 0;border:1px solid #e0e0e0;border-radius:4px;">';
    }

    html += '</td></tr></table>';
  }

  // --- Intermittent connectivity note ---
  html += '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:16px 0 24px 0;">' +
    '<tr><td style="padding:14px 18px;background-color:#e8f4fd;border-left:4px solid #4A90D9;border-radius:0 4px 4px 0;font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',Roboto,\'Helvetica Neue\',Arial,sans-serif;font-size:14px;line-height:1.5;color:#2c5282;">' +
    '<strong>Примечание:</strong> иногда соединение может временно прерываться. ' +
    'Если связь пропала, выключите и снова включите переключатель «Использовать прокси» (как в шагах 2 и 5). ' +
    'Обычно это восстанавливает подключение.' +
    '</td></tr></table>';

  // --- Sign-off ---
  html += '<p style="margin:0;font-size:14px;color:#888888;">Если возникнут вопросы, обратитесь к администратору.</p>';

  // Close all wrappers
  html += '</td></tr></table></td></tr></table></body></html>';

  return html;
}

/**
 * Load screenshot blobs from Google Drive. Returns empty object if IDs are not set.
 */
function loadScreenshotBlobs() {
  var blobs = {};
  for (var key in SCREENSHOT_IDS) {
    var fileId = SCREENSHOT_IDS[key];
    if (fileId && fileId !== "") {
      blobs[key] = DriveApp.getFileById(fileId).getBlob();
    }
  }
  return blobs;
}

/**
 * Send email with proxy link to user.
 */
function sendProxyEmail(email, username, tmeLink, tgLink) {
  var credentials = parseProxyUrl(tmeLink);
  var subject = "Персональная ссылка";

  // Try to load screenshots
  var imageBlobs = {};
  var screenshotKeys = [];
  try {
    imageBlobs = loadScreenshotBlobs();
    screenshotKeys = Object.keys(imageBlobs);
  } catch (e) {
    Logger.log("Screenshots not loaded: " + e.message);
  }

  var htmlBody = buildProxyEmailHtml(tmeLink, credentials, screenshotKeys);

  // Plain text fallback
  var plainBody = "Здравствуйте!\n\n" +
    "Ваша персональная ссылка готова:\n" + tmeLink + "\n\n" +
    "Данные для ручной настройки:\n" +
    "Сервер: " + credentials.server + "\n" +
    "Порт: " + credentials.port + "\n" +
    "Ключ: " + credentials.secret + "\n\n" +
    "Ссылка персональная. При обнаружении подозрительно высокой активности она будет заблокирована.\n" +
    "В случае блокировки обратитесь к администратору.\n\n" +
    "Если возникнут вопросы, обратитесь к администратору.";

  var options = {htmlBody: htmlBody};
  if (screenshotKeys.length > 0) {
    options.inlineImages = imageBlobs;
  }

  GmailApp.sendEmail(email, subject, plainBody, options);
}

/**
 * Run once to install the form submit trigger.
 */
function createTrigger() {
  ScriptApp.newTrigger("onFormSubmit")
    .forSpreadsheet(SpreadsheetApp.getActiveSpreadsheet())
    .onFormSubmit()
    .create();
}

/**
 * Manual test: add a test user via API.
 */
function testAddUser() {
  var result = addUser("test_user");
  Logger.log(JSON.stringify(result));
}

/**
 * Send a test email to admin for verifying the new template.
 */
function testSendEmail() {
  var testTmeLink = "https://t.me/proxy?server=tg.rigpa.space&port=443&secret=eea1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d479612e7275";
  sendProxyEmail(CONFIG.ADMIN_EMAIL, "test_user", testTmeLink, "");
  Logger.log("Test email sent to " + CONFIG.ADMIN_EMAIL);
}
