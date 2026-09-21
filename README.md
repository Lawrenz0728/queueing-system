# Members Services Queueing System

## Web pages

- `index.html` — customer queue page
- `customer_queue.html` — customer queue page
- `staff_queue_dashboard.html` — staff dashboard
- `tv_queue_display.html` — TV/display dashboard
- `register_staff.html` — redirects to the staff dashboard
- `customer_queue_backup.html` — backup copy of the alternate customer page

## Setup

1. Upload the project files to a GitHub repository.
2. Open the required SQL scripts from the `sql` folder.
3. Run the needed scripts in Supabase SQL Editor.
4. Confirm that the Supabase URL and publishable key in the HTML files match your project.
5. Enable GitHub Pages if you want to host the static HTML pages.

## Important security warning

The current staff dashboard is configured to open without login. Any person who obtains the page URL may be able to access queue information, depending on the Supabase policies you apply.

Before using this system publicly:
- Do not allow unrestricted anonymous updates.
- Use proper Supabase Row Level Security policies.
- Protect staff actions with authentication or server-side authorization.
- Review the SQL files before running them in production.
