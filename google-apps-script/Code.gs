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
 * Send email with proxy link to user.
 */
function sendProxyEmail(email, username, tmeLink, tgLink) {
  var subject = "Telegram Proxy — Sangha";
  var body = "Namaste!\n\n" +
    "Ваш персональный прокси для Telegram настроен.\n\n" +
    "Откройте эту ссылку на телефоне, чтобы подключиться:\n" +
    tmeLink + "\n\n" +
    "Или используйте эту ссылку напрямую в Telegram:\n" +
    tgLink + "\n\n" +
    "После нажатия Telegram предложит подключить прокси — нажмите «Подключить».\n\n" +
    "Эта ссылка персональная. Пожалуйста, не передавайте её другим людям.\n\n" +
    "Если возникнут проблемы, обратитесь к администратору.\n\n" +
    "— Sangha";

  GmailApp.sendEmail(email, subject, body);
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
