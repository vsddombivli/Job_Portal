# Sadharmik Jobs

A simple English/Hindi job portal for the Jain community. Candidates are approved through admin-created accounts. Employers do not need an account in version 1.

## Try it first

Open **demo.html** in a current browser. It is a self-contained interactive preview with fictional records. Switch between candidate and admin views using the top banner. Demo changes live only in the current tab; refresh resets them. It neither authenticates users nor sends applications to a backend. Do not use personal CVs in a shared demo session.

For the production frontend, serve this folder rather than opening index.html directly:

```sh
python3 -m http.server 8080
```

Visit http://localhost:8080. No build step or npm installation is needed. Node 20+ is needed only to run tests.

## Included functionality

- Candidate/admin workspaces with English and Hindi labels, responsive layouts, search and filters.
- Admin-created candidate accounts, eligibility/identity confirmation, mandatory first-login password change, current-password verification, admin-assisted reset, pause/reactivate.
- Private candidate profiles with mobile number, experience, current/expected annual CTC, preferred roles/cities, joining time, work preferences, private urgent-help flag and consent.
- Private PDF/DOCX CV storage (2 MB), browser-side text extraction, editable skill suggestions and mobile extraction. Manual profiles work without a CV.
- Explainable rule-based ranking by skills, role, location, experience and salary. Missing salary does not count as a mismatch. Mandatory skills are checked independently at application time on the server.
- Verified job creation/editing with draft, published and closed states; closing dates; private employer contact details.
- Atomic applications with duplicate prevention, profile/job/CV snapshots, candidate withdrawal, admin review/status updates and private CV download links.
- Email state visibly disabled throughout. Preferences are saved for future use, but no email sending, scheduled alert worker or Resend credentials are included.
- RLS, column privileges, immutable CV upload paths, server-side role/approval controls, session-version checks and admin activity records.

## Supabase setup — new project

Use a **separate new project**, not the donation-receipt application's database. These files do not connect to or modify that application.

1. Create a Supabase project. Keep the database password and service-role/secret keys private.
2. In SQL Editor, run `supabase/migrations/001_initial.sql` once. It creates tables, functions, RLS, indexes, a private `cvs` bucket and its policies. This is a new-install migration, not a rerunnable patch.
3. Authentication settings: enable email/password sign-in, disable public user sign-ups, and set the minimum password length to at least 12. Keep email confirmation enabled: this app's admin API creates already-confirmed accounts after the admin verifies email ownership. Do not configure SMTP or invite-by-email for this initial workflow.
4. In Authentication → Users, use **Add user / Create user** (not “Invite user”) to create your first admin with a temporary password and auto-confirm enabled. Its profile initially has candidate role and inactive state. Promote only that exact UUID with the SQL below.

```sql
-- Replace both UUID values with the SAME first admin's actual Auth user UUID.
update auth.users
set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
  || jsonb_build_object('approved',true,'access_version',gen_random_uuid()::text)
where id = 'YOUR-ADMIN-UUID';

update public.profiles p
set role='admin', active=true, must_change_password=true,
    full_name='Community Admin',
    access_version=u.raw_app_meta_data->>'access_version'
from auth.users u
where p.id=u.id and p.id='YOUR-ADMIN-UUID';
```

5. Sign out any existing admin browser session after promotion; log in again to obtain fresh metadata. Do not clear the mandatory-password flag by hand: the app will guide the admin through setting their own password.
6. Deploy the protected Edge Function. Using the Supabase CLI from this folder:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set ALLOWED_ORIGIN=https://YOUR_FRONTEND_DOMAIN
supabase functions deploy account-admin
```

The function automatically receives `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` in Supabase hosting. Never copy the service key into frontend files or share it in chat. `ALLOWED_ORIGIN` may be a comma-separated list, e.g. your production origin and `http://localhost:8080`. Use exact origins without trailing slashes. Although gateway `verify_jwt` is false for key compatibility, the function validates every JWT with Supabase Auth before authorising any action.

7. Edit **config.js** with your project URL, public **anon key** (legacy public JWT key supported by the pinned SDK), and an actual coordinator phone/email for support. These two public Supabase values may appear in frontend code. An anon key is not a service-role key.
8. Serve/upload the frontend files to a static HTTPS host. Do not expose the entire source package, tests or operational setup documents through your public site: deploy only `index.html`, `styles.css`, `app.js`, `core.js`, `demo.js`, `resume.js`, and `config.js`.
9. Run `tests/supabase-permissions.sql` in SQL Editor. It uses rollback-only fixtures to check candidate isolation, admin visibility, protected columns, applications and token/password restrictions. Then complete the live checklist below before onboarding real candidates.

## First real candidate

1. Admin signs in and changes their temporary password.
2. Open Candidates → Create candidate.
3. Confirm community eligibility, consent and email ownership outside the portal.
4. Set a temporary password of 12–128 characters; share it privately with the candidate. The app does not retain or email the plaintext password.
5. Candidate signs in, changes the temporary password, then signs in with their new password before accessing jobs/profiles.
6. Candidate builds their profile, optionally reads a CV and confirms skills/contact details. Upload and extraction are separate: a readable CV is helpful but not required to save a manual profile.
7. Admin publishes a verified opening. Candidate reviews it, agrees to share details and applies.
8. Admin reviews the stored application and handles employer coordination manually until email is added.

## Security model

- `profiles.role`, approval/activity flags, password state and session version cannot be updated by browser database calls. Profile read is limited to the owner and authorised admins.
- Public sign-up must be disabled; unsolicited Auth users would in any case receive inactive profiles.
- Employer email/source records are in an admin-only table; they are not embedded in candidate-visible jobs or application snapshots.
- Applications are inserted by a security-definer RPC, which rechecks profile readiness, consent, contact details, required skills and closing date. Duplicate protection is a database unique constraint.
- A submitted application keeps the exact CV path/profile snapshot used at submission. Later profile changes do not replace them. Referenced CVs cannot be deleted through candidate storage permissions; replacement uploads use a new UUID path.
- Signed CV links expire after 60 seconds. Downloaded copies cannot be recalled. Admins must handle CVs and contact details responsibly.
- Resets rotate session versions and remove the candidate's existing refresh sessions. Pausing/re-enabling does the same. Old JWTs fail protected RLS checks. If a multi-step reset fails, the account stays restricted; repeat the reset with a different temporary password.
- `admin_activity` records account, job and status changes without storing passwords. Failed attempts rely on platform auth logs.
- Account deletion is an assisted operation in this release. Verify identity, preserve only records required by your organisation's retention policy, remove CV objects using trusted administration, then remove the Auth user. Profile/application rows cascade; copied/downloaded data cannot be recalled. Never delete another candidate's account based only on an unverified email.

## Dependencies and limitations

- Supabase JS 2.49.8 (dynamic CDN import for live mode), PDF.js 4.10.38, Mammoth 1.9.0. Fonts load from Google Fonts, with system fallbacks. Network access to the appropriate CDNs and your Supabase project is needed; CV readers load only on demand. These pinned versions must be reviewed/updated periodically.
- The free-first parser extracts readable text, known skills and phone/email suggestions. It does **not** provide AI employment-history/education understanding, multilingual skill translation, scanned-document OCR or malware scanning. English skill names currently match best; explain/help candidates enter skills manually.
- Browser extraction may fail on scanned, password-protected or unusual PDFs. Upload rejects files beyond 2 MB, and PDF extraction rejects over 30 pages. Never render extracted DOCX HTML; only raw text is processed. A private upload does not imply a malware-free file.
- Candidate interface and main admin labels support Hindi. Employer/job content and extracted skill names retain their source language. Some provider errors and operational admin messages remain English.
- “Email confirmed” means the admin verified ownership externally; it is not proof of a delivered confirmation email. Changing login email requires trusted administrative assistance in v1.
- Rule-based scores are helpful rankings, not hiring decisions. Age and employment gaps are not scoring inputs. Experience ranges are preferences; mandatory skills are eligibility gates. Candidates can browse every currently published opening.
- Matching incorporates work-mode and employment-type preferences within the location and role weights. Availability and education do not yet gate matching; only mandatory skills gate applications.
- Lists currently load all accessible records. For the intended 100–500 person pilot this keeps the app simple; add server-side pagination before large application volumes.
- Email, provider login, export, saved jobs, push/SMS/WhatsApp notifications, self-registration and automatic account deletion are not included. Password recovery is admin-assisted. Email alert preferences do not schedule anything yet.
- Free-tier capacity depends on CV sizes/downloads, not just candidate count. 500 files at the full 2 MB cap approximately fill 1 GB; application CV versions add storage. Encourage smaller files, monitor usage, and establish a retention/backup process. Free projects can pause when inactive; arrange a paid plan/backups when reliability requires it.
- No Supabase project credentials were supplied during creation. SQL, live authentication, storage policies and Edge Functions still need execution/verification in your own project before production use.

## Validation

```sh
npm test
node --check app.js
node --check core.js
node --check resume.js
```

Automated tests cover parsing, matching (including work mode/type), eligibility, closing dates, escaping, forms and validation, demo screen rendering, filters, bilingual navigation, password screen and immutable snapshots. All 24 automated checks passed during creation. They use a small DOM stub, not a real browser. A browser binary and live Supabase project were unavailable, so visual/end-to-end browser testing and backend integration execution remain pending.

Live acceptance checklist:

- [ ] Migration runs cleanly on a new project; rollback permission checks pass.
- [ ] Bootstrap admin can log in, set own password and create/reset/pause candidates.
- [ ] Temporary-password candidates cannot read jobs, upload files or apply through direct API requests.
- [ ] Candidate A cannot read Candidate B's profile, CV or application; candidate cannot read employer contacts.
- [ ] Previous access/refresh sessions fail after reset/pause. Password changes verify the current password.
- [ ] Text PDF and DOCX extraction work; scanned/oversized/incorrect files show useful feedback; manual entry still works.
- [ ] Upload a CV, apply, upload a replacement: application still opens the original CV.
- [ ] Expired/draft/closed jobs cannot receive applications; duplicate submissions produce one record.
- [ ] Candidate withdrawal cannot be reversed by the admin status form.
- [ ] Applicant review shows the submitted phone/profile/CV and status changes reach the candidate portal.
- [ ] Hindi and English flows, keyboard navigation, focus, phone layout, downloads and CDN loading work in real browsers.
- [ ] Email remains visibly disabled; no notification is falsely marked sent.

## Change history

### 1.0.0 — 21 October 2026

Initial implementation: English/Hindi frontend, self-contained demo, Supabase migration, protected account Edge Function, private CV storage, rule-based matching, applications/admin review, account controls, automated checks and deployment guide. Email deliberately disabled per agreed first-release workflow.
