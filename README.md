# Postfix Mail System Setup for mail.100to1shot.com

This repository contains automated scripts to set up a complete Postfix mail system for your subdomain `mail.100to1shot.com`, enabling SMTP functionality for your website to send emails to users.

## 🚀 Quick Start

### Prerequisites

- Ubuntu/Debian server with root access
- Domain `100to1shot.com` with subdomain `mail.100to1shot.com`
- DNS access to configure required records
- SMTP relay provider credentials (Gmail, Mailgun, etc.)

### Installation

1. **Download and run the main setup script:**
   ```bash
   sudo ./setup_postfix_mail.sh
   ```

2. **Configure SMTP relay (required for sending emails):**
   ```bash
   sudo ./configure_smtp_relay.sh
   ```

## 📋 What the Scripts Do

### Main Setup Script (`setup_postfix_mail.sh`)

The main script automatically:

- ✅ Updates system packages
- ✅ Installs Postfix and required dependencies
- ✅ Configures firewall rules (ports 25, 587, 465)
- ✅ Sets system hostname to `mail.100to1shot.com`
- ✅ Configures Postfix main settings
- ✅ Sets up SASL authentication
- ✅ Configures submission port (587)
- ✅ Creates SSL certificates for TLS
- ✅ Sets up mail aliases and virtual domains
- ✅ Starts and enables Postfix service
- ✅ Tests mail configuration
- ✅ Creates detailed setup summary

### SMTP Relay Configuration Script (`configure_smtp_relay.sh`)

The companion script provides:

- 🔧 Interactive SMTP provider selection
- 🔧 Credential configuration for popular providers
- 🔧 SMTP relay testing
- 🔧 Configuration management
- 🔧 Easy removal of relay settings

## 🌐 DNS Configuration Required

After running the setup script, configure these DNS records:

### A Record
```
mail.100to1shot.com    A    YOUR_SERVER_IP
```

### PTR Record (Reverse DNS)
```
YOUR_SERVER_IP    PTR    mail.100to1shot.com
```

### SPF Record
```
100to1shot.com    TXT    "v=spf1 a mx include:mail.100to1shot.com ~all"
```

### DKIM Record
Configure with your SMTP provider (Gmail, Mailgun, etc.)

### DMARC Record
```
_dmarc.100to1shot.com    TXT    "v=DMARC1; p=quarantine; rua=mailto:admin@100to1shot.com"
```

## 📧 SMTP Providers Supported

The configuration script supports:

1. **Gmail** - Requires App Password (2FA must be enabled)
2. **Outlook/Hotmail** - Standard authentication
3. **Yahoo** - Standard authentication
4. **Mailgun** - API-based authentication
5. **SendGrid** - API-based authentication
6. **Amazon SES** - AWS credentials
7. **Custom SMTP** - Any SMTP server

## 🔧 Website Integration

For your website to send emails, use these SMTP settings:

```
SMTP Server: mail.100to1shot.com
Port: 587 (with TLS) or 465 (with SSL)
Authentication: Required
Username: Your configured email address
Password: Your configured password/app password
From Address: noreply@100to1shot.com
```

### PHP Example
```php
<?php
$to = "user@example.com";
$subject = "Welcome to our website";
$message = "Thank you for signing up!";
$headers = "From: noreply@100to1shot.com\r\n";
$headers .= "Reply-To: admin@100to1shot.com\r\n";
$headers .= "X-Mailer: PHP/" . phpversion();

// Send email using mail() function
mail($to, $subject, $message, $headers);
?>
```

### Node.js Example
```javascript
const nodemailer = require('nodemailer');

const transporter = nodemailer.createTransporter({
    host: 'mail.100to1shot.com',
    port: 587,
    secure: false, // true for 465, false for other ports
    auth: {
        user: 'your-email@100to1shot.com',
        pass: 'your-password'
    }
});

const mailOptions = {
    from: 'noreply@100to1shot.com',
    to: 'user@example.com',
    subject: 'Welcome to our website',
    text: 'Thank you for signing up!'
};

transporter.sendMail(mailOptions, (error, info) => {
    if (error) {
        console.log(error);
    } else {
        console.log('Email sent: ' + info.response);
    }
});
```

## 🔍 Troubleshooting

### Check Postfix Status
```bash
sudo systemctl status postfix
sudo postfix check
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
mailq
```

### Common Issues

1. **Emails going to spam**: Configure SPF, DKIM, and DMARC records
2. **Authentication failed**: Check SMTP credentials in `/etc/postfix/sasl_passwd`
3. **Connection refused**: Ensure firewall allows ports 25, 587, 465
4. **DNS issues**: Verify A and PTR records are correctly configured

## 📁 Important Files

- `/etc/postfix/main.cf` - Main Postfix configuration
- `/etc/postfix/master.cf` - Service configuration
- `/etc/postfix/sasl_passwd` - SMTP relay credentials
- `/etc/postfix/aliases` - Mail aliases
- `/etc/ssl/postfix/mail.crt` - SSL certificate
- `/etc/ssl/postfix/mail.key` - SSL private key
- `/var/log/mail.log` - Mail logs
- `/root/postfix_setup_summary.txt` - Setup summary

## 🔒 Security Features

- ✅ TLS/SSL encryption for email transmission
- ✅ SASL authentication for SMTP relay
- ✅ Firewall configuration for required ports only
- ✅ Secure file permissions (600 for credentials)
- ✅ Disabled VRFY command
- ✅ Helo restrictions
- ✅ Message size limits

## 📞 Support

If you encounter issues:

1. Check the setup logs: `/var/log/postfix_setup.log`
2. Review the configuration summary: `/root/postfix_setup_summary.txt`
3. Verify DNS records are properly configured
4. Test with a simple email first
5. Check your SMTP provider's documentation for specific requirements

## 🎯 Next Steps

After successful setup:

1. Configure your website to use the SMTP settings
2. Test email sending from your application
3. Monitor mail logs for any issues
4. Consider setting up email monitoring
5. Implement proper email templates for your website

---

**Note**: This setup creates a send-only mail server. For receiving emails, additional configuration would be required including IMAP/POP3 setup and proper MX records.