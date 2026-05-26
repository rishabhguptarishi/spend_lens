# Security Guide – SpendLens

This app stores financial records. Follow these practices to keep data secure.

## Implemented

### Authentication
- **Devise** – Email/password auth with bcrypt (cost 12)
- **Session timeout** – 30 min inactivity
- **Account lockout** – 5 failed attempts → 1 hr lock
- **Password** – Min 8 chars
- **Remember me** – Tokens cleared on sign out

### Authorization
- All controllers use `authenticate_user!`
- Queries scoped by `current_user` (no IDOR)
- Bank accounts, transactions, categories are user-scoped

### Data Protection
- **Filtered logs** – Amounts, descriptions, bank names, files not logged
- **SSL** – `force_ssl` in production
- **Secure cookies** – Via `force_ssl`

### File Uploads
- Allowed types: CSV, PDF only
- Max size: 25 MB
- Validation in controller and model

## Recommendations

### Production Checklist

1. **HTTPS**
   - Use TLS (production has `force_ssl`)
   - Set `config.hosts` for your domain

2. **Secrets**
   - Use `rails credentials:edit` or env vars for secrets
   - Never commit `.env` or `config/master.key`
   - Rotate `secret_key_base` if exposed

3. **Database**
   - Use `SPEND_LENS_DATABASE_PASSWORD` or `DATABASE_URL`
   - Enable DB encryption at rest (provider-dependent)
   - Restrict DB access

4. **Email**
   - Use TLS for SMTP
   - Set `config.action_mailer.default_url_options = { host: 'yourdomain.com' }`

5. **Host**
   - Configure `config.hosts` in production
   - Disable DNS rebinding for your domain

### Rate Limiting (rack-attack)
- **Login** – 5 attempts/min by IP, 5/min by email
- **Upload** – 10/min per IP
- **Password reset** – 3/hour per IP

### Content Security Policy
- Enabled in production; Vite dev server allowed in development
- Restricts scripts, styles, fonts, images to self + https
- **Audit logging** – Log sensitive actions (login, export, delete)
- **2FA** – Enable Devise `:two_factor_authenticatable` for high-risk users
- **Email confirmation** – Enable Devise `:confirmable` for new signups

### Reporting

If you find a vulnerability, email security@yourdomain.com (do not open a public issue).
