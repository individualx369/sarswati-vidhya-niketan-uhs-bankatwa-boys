# Admin setup

The admin UI is at `/admin/` and uses server-side authentication. No admin password is stored in frontend JavaScript or HTML.

## Required hosting environment variables

Set these in Vercel (or another server-side hosting environment), **not in GitHub**:

- `ADMIN_USERNAME` = your chosen admin username
- `ADMIN_PASSWORD` = a new strong admin password
- `ADMIN_SESSION_SECRET` = a long random secret (at least 32 random bytes)

After adding or changing environment variables, redeploy the project.

## Security notes

- The browser sends credentials only to `/api/admin/login` over HTTPS.
- The server creates an HttpOnly, Secure, SameSite=Strict session cookie.
- The password is never rendered into the frontend.
- This first stage provides secure server-side session authentication for a single administrator. The next stage should connect the content manager to Supabase/Postgres with Row Level Security so notices, gallery, staff, achievements and downloads persist safely.
