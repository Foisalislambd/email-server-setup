# SMTP Test Project

This project helps you test SMTP authentication for your mail server at `mail.100to1shot.com`.

## 🚀 Quick Start

### 1. Install Dependencies
```bash
npm install
```

### 2. Set Your Password
Edit the password in the test files:
- `test-smtp.js` - Line 15: Replace `YOUR_PASSWORD_HERE`
- `simple-test.js` - Line 12: Replace `YOUR_PASSWORD_HERE`

### 3. Run Tests

#### Simple Test (Quick)
```bash
npm run test-simple
```

#### Comprehensive Test
```bash
npm run test
```

#### Debug Mode (Verbose Output)
```bash
npm run test-debug
```

## 📋 What the Tests Do

### Simple Test (`simple-test.js`)
- Tests basic SMTP connection
- Sends one test email
- Shows clear success/failure messages

### Comprehensive Test (`test-smtp.js`)
- Tests multiple host configurations
- Tests different authentication methods
- Provides detailed error information
- Shows troubleshooting tips

## 🔧 Configuration Options

The tests try these configurations automatically:

### Hosts
- `localhost`
- `mail.100to1shot.com`
- `127.0.0.1`

### Authentication Methods
- Username only: `noreply`
- Full email: `noreply@100to1shot.com`

## 📊 Expected Results

### ✅ Success
```
✅ Connection successful!
✅ Email sent successfully!
Message ID: <20250926090009.B887F47D17@mail.100to1shot.com>
```

### ❌ Failure
```
❌ Connection failed!
Error: Invalid login: 535 5.7.8 Error: authentication failed
Code: EAUTH
Response: 535 5.7.8 Error: authentication failed: authentication failure
```

## 🔧 Troubleshooting

If tests fail:

1. **Check Password**: Make sure you set the correct password
2. **Check User**: Verify user exists: `sasldblistusers2 -f /etc/sasldb2`
3. **Check Postfix**: `systemctl status postfix`
4. **Check Logs**: `tail -f /var/log/mail.log`
5. **Check Configuration**: `postconf | grep sasl`

## 📧 Email Settings for Your Website

Once tests pass, use these settings in your website:

```javascript
const transporter = nodemailer.createTransporter({
    host: 'localhost', // or 'mail.100to1shot.com'
    port: 587,
    secure: false,
    auth: {
        user: 'noreply',
        pass: 'your_password'
    },
    tls: {
        rejectUnauthorized: false
    }
});
```

## 🎯 Next Steps

1. Run the tests
2. If they pass, update your website with the working configuration
3. If they fail, check the troubleshooting steps
4. Run the master.cf update script: `sudo ./update_master_cf.sh`