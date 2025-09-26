# 📧 Domain-based SMTP Setup Script - বাংলা ব্যাখ্যা

## 🎯 **স্ক্রিপ্টের উদ্দেশ্য**
এই স্ক্রিপ্টটি আপনার নিজের ডোমেইন দিয়ে ইমেইল পাঠানোর জন্য Postfix SMTP সার্ভার সেটআপ করে। Gmail বা অন্য সার্ভিস ব্যবহার না করে আপনার নিজের ডোমেইন ব্যবহার করে।

## 📝 **স্ক্রিপ্টের অংশগুলো:**

### **1. প্রাথমিক সেটআপ (Lines 1-37)**
```bash
#!/bin/bash
set -e
```
- **ব্যাখ্যা**: স্ক্রিপ্ট শুরু এবং কোনো এরর হলে বন্ধ হয়ে যাবে
- **রঙের কোড**: সবুজ, লাল, হলুদ, নীল রঙের জন্য ভেরিয়েবল
- **লগিং ফাংশন**: সফলতা, সতর্কতা, এরর দেখানোর জন্য

### **2. ব্যবহারকারীর ইনপুট নেওয়া (Lines 44-57)**
```bash
read -p "Enter your domain name: " DOMAIN
read -p "Enter email address: " EMAIL_ADDRESS
read -s -p "Enter email password: " EMAIL_PASSWORD
read -p "Enter SMTP port: " SMTP_PORT
read -p "Enter server hostname: " SERVER_HOSTNAME
read -p "Install Let's Encrypt SSL certificate: " INSTALL_SSL
```
- **DOMAIN**: আপনার ডোমেইন (যেমন: 100to1shot.com)
- **EMAIL_ADDRESS**: ইমেইল ঠিকানা (যেমন: noreply@100to1shot.com)
- **EMAIL_PASSWORD**: ইমেইলের পাসওয়ার্ড
- **SMTP_PORT**: SMTP পোর্ট (ডিফল্ট: 587)
- **SERVER_HOSTNAME**: সার্ভারের নাম (যেমন: mail.100to1shot.com)
- **INSTALL_SSL**: SSL সার্টিফিকেট ইনস্টল করবে কিনা (y/n)

### **3. প্যাকেজ ইনস্টলেশন (Lines 61-69)**
```bash
apt update
apt install -y postfix libsasl2-modules libsasl2-2 ca-certificates openssl
```
- **postfix**: ইমেইল সার্ভার সফটওয়্যার
- **libsasl2-modules**: অথেনটিকেশন মডিউল
- **ca-certificates**: SSL সার্টিফিকেট
- **openssl**: SSL টুলস
- **certbot**: Let's Encrypt SSL সার্টিফিকেটের জন্য (যদি y নির্বাচন করা হয়)

### **4. Postfix কনফিগারেশন (Lines 71-133)**
```bash
cat > /etc/postfix/main.cf << EOF
myhostname = $SERVER_HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = \$myhostname, \$mydomain, localhost, localhost.localdomain
EOF
```
- **myhostname**: সার্ভারের নাম (mail.100to1shot.com)
- **mydomain**: আপনার ডোমেইন (100to1shot.com)
- **myorigin**: ইমেইলের উৎস
- **mydestination**: গন্তব্য ডোমেইন

### **5. SASL অথেনটিকেশন (Lines 139-149)**
```bash
cat > /etc/postfix/sasl_passwd << EOF
$SERVER_HOSTNAME:$SMTP_PORT $EMAIL_ADDRESS:$EMAIL_PASSWORD
EOF
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
```
- **sasl_passwd**: ইমেইল অ্যাকাউন্টের পাসওয়ার্ড স্টোর করে
- **chmod 600**: ফাইলটি শুধু root পড়তে পারবে
- **postmap**: পাসওয়ার্ড ফাইল প্রসেস করে

### **6. SSL সার্টিফিকেট ইনস্টলেশন (Lines 171-219)**

#### **Let's Encrypt SSL (যদি y নির্বাচন করা হয়):**
```bash
certbot certonly --standalone -d "$SERVER_HOSTNAME"
```
- **certbot**: Let's Encrypt SSL সার্টিফিকেট ইনস্টল করে
- **--standalone**: নিজে নিজে SSL ইনস্টল করে
- **-d**: শুধু subdomain এর জন্য (mail.100to1shot.com)

#### **Self-signed SSL (যদি n নির্বাচন করা হয়):**
```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
    -out /etc/ssl/certs/ssl-cert-snakeoil.pem \
    -subj "/CN=$SERVER_HOSTNAME"
```
- **openssl**: নিজের SSL সার্টিফিকেট তৈরি করে
- **-x509**: X.509 সার্টিফিকেট
- **-nodes**: পাসওয়ার্ড ছাড়া
- **-days 365**: ১ বছর বৈধ
- **-newkey rsa:2048**: 2048-bit RSA কী

### **7. ইমেইল হেডার কনফিগারেশন (Lines 154-159)**
```bash
cat > /etc/postfix/header_checks << EOF
/^From:.*/ REPLACE From: $EMAIL_ADDRESS
/^Reply-To:.*/ REPLACE Reply-To: $EMAIL_ADDRESS
EOF
```
- **header_checks**: ইমেইলের হেডার ঠিক করে
- **From**: সব ইমেইলের From ঠিকানা একই রাখে
- **Reply-To**: Reply-To ঠিকানা সেট করে

### **8. মেইলনেম এবং অ্যালিয়াস সেটআপ (Lines 223-228)**
```bash
echo "$DOMAIN" > /etc/mailname
echo "root: $EMAIL_ADDRESS" >> /etc/aliases
newaliases
```
- **mailname**: ডোমেইন নাম সেট করে
- **aliases**: root ইমেইল আপনার ইমেইলে ফরওয়ার্ড করে
- **newaliases**: অ্যালিয়াস ডাটাবেস আপডেট করে

### **9. Postfix সার্ভিস শুরু (Lines 230-235)**
```bash
systemctl enable postfix
systemctl restart postfix
postfix reload
```
- **enable**: সার্ভিস অটোস্টার্ট হবে
- **restart**: সার্ভিস রিস্টার্ট করে
- **reload**: কনফিগারেশন রিলোড করে

### **10. টেস্ট ইমেইল পাঠানো (Lines 237-266)**
```bash
echo "Test message from $DOMAIN SMTP server" | \
mail -s "Test Email from $DOMAIN" \
-a "From: $EMAIL_ADDRESS" "$EMAIL_ADDRESS"
```
- **mail**: টেস্ট ইমেইল পাঠায়
- **-s**: সাবজেক্ট
- **-a**: হেডার যোগ করে
- **From**: আপনার ইমেইল ঠিকানা থেকে পাঠায়

### **11. ডকুমেন্টেশন তৈরি (Lines 268-422)**
স্ক্রিপ্টটি একটি বিস্তারিত গাইড তৈরি করে যাতে আছে:
- **PHP কোড উদাহরণ**
- **Python কোড উদাহরণ**
- **Node.js কোড উদাহরণ**
- **DNS রেকর্ড সেটআপ**
- **ট্রাবলশুটিং গাইড**

## 🔧 **কীভাবে কাজ করে:**

### **ইনপুট:**
```
Domain: 100to1shot.com
Email: noreply@100to1shot.com
Hostname: mail.100to1shot.com
SSL: y
```

### **প্রক্রিয়া:**
1. **প্যাকেজ ইনস্টল** → Postfix, SSL টুলস
2. **Postfix কনফিগার** → আপনার ডোমেইনের জন্য
3. **SSL ইনস্টল** → শুধু subdomain এ (mail.100to1shot.com)
4. **অথেনটিকেশন সেটআপ** → আপনার ইমেইল অ্যাকাউন্ট
5. **সার্ভিস শুরু** → Postfix চালু
6. **টেস্ট** → ইমেইল পাঠানোর টেস্ট

### **আউটপুট:**
- **ইমেইল সার্ভার**: mail.100to1shot.com
- **SSL সার্টিফিকেট**: শুধু subdomain এ
- **ইমেইল ঠিকানা**: user@100to1shot.com
- **SMTP পোর্ট**: 587

## 🎯 **মূল বৈশিষ্ট্য:**

1. **ডোমেইন-ভিত্তিক**: আপনার নিজের ডোমেইন ব্যবহার
2. **SSL নিরাপত্তা**: Let's Encrypt বা Self-signed
3. **Subdomain আলাদা**: mail.100to1shot.com (মূল ডোমেইন অক্ষত)
4. **অটোমেটিক**: সব কিছু অটো কনফিগার
5. **ডকুমেন্টেশন**: বিস্তারিত গাইড সহ

## 🚀 **ব্যবহার:**
```bash
sudo ./setup_domain_smtp.sh
```

এই স্ক্রিপ্টটি আপনার জন্য একটি সম্পূর্ণ ইমেইল সার্ভার তৈরি করবে যা আপনার নিজের ডোমেইন ব্যবহার করে! 📧✨