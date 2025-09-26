# Postfix Mail Server Auto-Setup Script

This script automatically sets up a complete Postfix mail server for your subdomain `mail.100to1shot.com` without using any third-party mail providers. It's designed specifically for SMTP-only functionality to send emails from your website.

## Features

- ✅ **Complete Postfix Configuration**: Automated setup with optimal settings
- ✅ **DKIM Authentication**: Email authentication to prevent spam
- ✅ **Security Hardening**: Firewall rules and fail2ban protection
- ✅ **Send-Only Setup**: Optimized for website email sending
- ✅ **DNS Instructions**: Complete DNS configuration guide
- ✅ **Testing Tools**: Built-in test script to verify setup
- ✅ **Logging**: Comprehensive logging for troubleshooting

## Quick Start

1. **Run the setup script as root:**
   ```bash
   sudo ./setup_postfix_mail.sh
   ```

2. **Configure DNS records** (see `DNS_SETUP_INSTRUCTIONS.txt`)

3. **Test the setup:**
   ```bash
   sudo ./test_mail.sh
   ```

## What the Script Does

### 1. System Preparation
- Checks system requirements
- Updates all packages
- Sets proper hostname (`mail.100to1shot.com`)

### 2. Package Installation
- Postfix (mail server)
- OpenDKIM (email authentication)
- UFW (firewall)
- Fail2ban (security)
- Essential utilities

### 3. Postfix Configuration
- Configures as send-only SMTP server
- Sets up proper hostname and domain
- Configures security settings
- Optimizes for website email sending

### 4. DKIM Setup
- Generates DKIM key pair
- Configures email authentication
- Provides public key for DNS

### 5. Security Configuration
- Configures firewall rules
- Sets up fail2ban protection
- Implements security best practices

### 6. Testing & Documentation
- Creates test script
- Generates DNS configuration guide
- Provides SMTP settings for your website

## SMTP Configuration for Your Website

After running the script, use these settings in your website:

```
Host: mail.100to1shot.com
Port: 25
Security: None
Authentication: None
```

### PHP Example (PHPMailer)
```php
$mail = new PHPMailer(true);
$mail->isSMTP();
$mail->Host = 'mail.100to1shot.com';
$mail->Port = 25;
$mail->SMTPAuth = false;
$mail->SMTPSecure = false;
```

### Node.js Example (Nodemailer)
```javascript
const transporter = nodemailer.createTransporter({
    host: 'mail.100to1shot.com',
    port: 25,
    secure: false,
    auth: {
        // No authentication needed for local SMTP
    }
});
```

## DNS Configuration Required

The script will generate a `DNS_SETUP_INSTRUCTIONS.txt` file with all the DNS records you need to configure:

1. **A Record**: Point `mail.100to1shot.com` to your server IP
2. **SPF Record**: Prevent email spoofing
3. **DKIM Record**: Email authentication
4. **DMARC Record**: Email policy (optional)

## Files Created

- `setup_postfix_mail.sh` - Main setup script
- `test_mail.sh` - Test script (created after setup)
- `DNS_SETUP_INSTRUCTIONS.txt` - DNS configuration guide
- `/var/log/postfix_setup.log` - Setup log file

## Troubleshooting

### Check Service Status
```bash
sudo systemctl status postfix
sudo systemctl status opendkim
```

### View Mail Logs
```bash
sudo tail -f /var/log/mail.log
```

### Test Email Sending
```bash
echo "Test message" | mail -s "Test Subject" your-email@example.com
```

### Check Mail Queue
```bash
sudo mailq
```

## Security Notes

- This setup is configured for **send-only** email functionality
- SMTP ports are not exposed to the internet (send-only)
- Firewall is configured to block unnecessary ports
- Fail2ban protects against brute force attacks
- DKIM authentication prevents email spoofing

## Requirements

- Ubuntu/Debian Linux system
- Root access (sudo)
- At least 1GB free disk space
- Internet connection for package downloads

## Support

If you encounter issues:

1. Check the log file: `/var/log/postfix_setup.log`
2. Run the test script: `./test_mail.sh`
3. Verify DNS configuration
4. Check firewall settings: `sudo ufw status`

## License

This script is provided as-is for educational and development purposes. Use at your own risk in production environments.