> The following document is a user manual for the Apexo project. If you would like to know about the technical details, or you would like to build the application yourself please refer to the [Github repository](https://github.com/elselawi/apexo) and read through [readme.md](https://github.com/elselawi/apexo/blob/master/README.md).


## Downloading

You can download the application from the website: [apexo.app](https://apexo.app). Click ___"Get started"___ and choose your platform (windows, android ...etc).

You can also download the application directly from the [Github repository](https://github.com/elselawi/apexo/tree/master/dist).

## Server setup

Before you can use the application, you must setup your server. setting up your server is a straightforward task and doesn't need any coding or terminal commands.

The server must run a freshly installed [Pocketbase](https://pocketbase.io).

There are multiple companies that you can rent servers from, my recommendation is to use [Digital Ocean](https://m.do.co/c/2f1ffd8f0fe4).

Using the link above (which is an affiliate link) you can get 200$ of credit in digital ocean for free.

#### Step by step

1. [Register a new account using this link to get 200$ for free](https://m.do.co/c/2f1ffd8f0fe4).

2. [Create a new droplet selecting Pocketbase as an image](https://cloud.digitalocean.com/droplets/new?i=a3cfd1&region=nyc1&size=s-1vcpu-1gb&appId=173923600&image=doteamaccount-pocketbase&type=applications&refcode=2f1ffd8f0fe4).

3. After creating the droplet, you must allow up to 3 minutes for the server to start.

4. Next, head to your droplet page and click on "access" then "launch droplet console".
    ![Access](https://raw.githubusercontent.com/elselawi/apexo/master/docs/manual_imgs/access.png)

5. Once you have access to the console, run the following command:
    ```
    /opt/pocketbase/pocketbase superuser create admin@example.com password123456789
    ```
    change `admin@example.com` to your email and  `password123456789` to your password. This command will create a new admin user.


6. If you have a custom domain (preferable) run the following command: `nano /etc/caddy/Caddyfile` and replace the first line with your domain (e.g. `example.com`). This will allow you to access the server through the ___https___ protocol (https://example.com). You will also need to setup your domain DNS to point to the server (this can vary depending on your domain provider, but it's usually a straight forward task done through the domain provider's website).

7. Login to your server either through the IP that is set to your droplet or through the domain you have set to make sure that your server and your credentials work. use the credentials you have set in step 5. The pocket dashboard is located at `https://SERVER/_/`, where SERVER is the IP or domain you have set.

8. Open the apexo app and enter the server address (either IP or custom domain) and you credentials (email & password) you have set in step 5. The application will automatically verify the server and set it up further. Then, you can start using the application once it fully loads.


## Best practices

While your application is now ready and working there are further steps to take to make sure your application is secure and reliable. This is especially important if you are setting it up for real world use.

#### Setting up email

Setting up email is useful for sending login alert notifications, password reset email, and other emails.

Go to the settings screen and find the **SMTP Settings** section. Expand it to see the configuration panel.

First, enable the toggle **SMTP enabled** to activate email sending.

You can use the **preset buttons** (Gmail / Outlook) to quickly fill in the correct host and port values, or enter them manually:

| Field | Description |
|-------|-------------|
| **SMTP host** | Your email provider's SMTP server (e.g., `smtp.gmail.com`) |
| **SMTP port** | Typically `587` for TLS |
| **TLS mode** | Choose _Auto_ to let the server negotiate, or _Always_ to force TLS |
| **SMTP username** | Your email address (e.g., `you@gmail.com`) |
| **SMTP password** | Your email password or app-specific password (use the eye icon to toggle visibility) |

> If you use 2‑step verification, you must generate an **app password** instead of your normal password:
> - [Gmail app passwords](https://myaccount.google.com/apppasswords)
> - [Outlook app passwords](https://account.live.com/proofs/Manage/additional)

Fill in the sender details that will appear on outgoing emails:

| Field | Description |
|-------|-------------|
| **Sender name** | The display name recipients will see (e.g., "My Clinic") |
| **Sender email** | The address emails will come from (e.g., `noreply@example.com`) |
| **Local name** | The local hostname used in SMTP EHLO (e.g., `mine.apexo.app`) |

Click **Save** to persist your settings. You can also click **Test** to send a test email to your own address and verify the configuration works.

> **Note:** Some hosting providers block port 25 and other common SMTP ports. The settings panel will show a warning if this may be an issue.

#### Setting up backups

Setting up backups is useful for making sure you don't lose your data in case of a server crash or a hacker attack. You can set up a backup schedule to run automatically, and also create manual backups at any time.

Go to the settings screen and find the **Backups** section. Expand it to see the full panel.

##### Managing existing backups

The top portion of the panel lists all existing backup files, each showing its date and file size. For each backup you can:

- **Download**: Get a shareable download link to save the backup file locally
- **Delete**: Remove a backup you no longer need
- **Restore**: Replace all current data with the data from this backup (⚠️ this cannot be undone)

Use the toolbar buttons to:
- **Create new**: Generate a fresh backup immediately
- **Upload**: Select a backup file from your device to upload to the server
- **Refresh**: Reload the backup list from the server

##### Configuring automatic backups

Below the backup list, the **Backup configuration** panel lets you schedule automatic backups:

1. Enable the toggle **Auto backup enabled** to activate scheduled backups.

2. Choose a **schedule preset** from the dropdown, or type a custom [cron expression](https://en.wikipedia.org/wiki/Cron):
   - Every hour · Every 6 hours · Every 12 hours
   - Daily (midnight) · Daily (3 AM) · Weekly (Sunday) · Monthly (1st)

3. Set **Max backups to keep**, older backups beyond this count will be automatically deleted.

4. Optionally enable **S3 storage for backups** to store backup files on your S3 provider instead of the server's local storage. When enabled, fill in your S3 credentials (endpoint, bucket, region, access key, secret key, and force path style).

Click **Save** to persist your schedule, and **Test** to verify the S3 connection if configured.

#### Setting up S3

What's S3? S3 is cloud storage specifically designed for storing files. Think of it as yet-another-server that you'll setup specifically for storing the photos you upload to the application.

While your server can already handle a lot of file uploads (photos), setting up S3 is useful if you're planning to store too many photos (tens of thousands) especially if you're using the application for a large clinic.

For example the cheapest droplet in digital ocean (5$ a month) already has 25GB of storage which can typically hold around 5000 to 10000 photos. You can upgrade your droplet to a larger one, but it would get quite costly as you upgrade to a larger and then larger one, and if you decide to port the server or the files to another hosting provider, you'll have to do it manually and it can get quite expensive or technical or both.

Having a separate S3 bucket for your photos is a good idea because you can scale it up and down as you need it. And you can ditch the hosting provider any time and move to another one without having to worry about the data as long as you have the backups.

To setup S3, first you'll have to register with an S3 provider. The following are some of the most popular S3 and how much would it cost for 250GB of storage:

- [AWS S3](https://aws.amazon.com/s3/) __Free for 5GB__, ~$5.6 for 250GB
- [Digital Ocean Spaces](https://www.digitalocean.com/products/spaces/) _No free tier_, ~$5 for 250GB
- [Scaleway](https://www.scaleway.com/en/object-storage/) _No free tier_, ~$3.75 for 250GB
- [Backblaze B2](https://www.backblaze.com/b2/cloud-storage.html) _No free tier_, ~$1.5 for 250GB
- [Google Cloud Storage](https://cloud.google.com/storage) __Free for 5GB__, ~$5 for 250GB
- [iDrive](https://www.idrive.com/s3-storage-e2/) _No free tier_, ~$1.5 for 250GB
- [Cloudflare R2](https://www.cloudflare.com/products/r2/) __Free for 10GB__, ~$3.5 for 250GB

Once you've registered with an S3 provider, you'll have to create a bucket and get the following information. You can find the documentation for each provider on how to create a bucket and obtain the credentials.

Go to the settings screen and find the **S3 Settings** section. Expand it and enable the **S3 enabled** toggle, then fill in your credentials:

| Field | Description |
|-------|-------------|
| **Endpoint** | Your S3 provider's endpoint URL (e.g., `https://s3.amazonaws.com`) |
| **Bucket** | The name of your S3 bucket (e.g., `my-bucket`) |
| **Region** | Your bucket's region (e.g., `us-east-1`) |
| **Access key** | Your S3 access key (e.g., `AKIA...`) |
| **Secret key** | Your S3 secret key (use the eye icon to toggle visibility) |
| **Force path style** | Enable if your S3 provider requires path-style URLs instead of virtual-hosted–style |

Click **Save** to persist the configuration, then click **Test** to verify the connection. A success or error message will appear at the bottom of the panel.

## How to use

### Accounts

In Apexo, each staff member can have their own account. Accounts are managed from the **Accounts** screen.

There are two account types:

| Type | Badge | Description |
|------|-------|-------------|
| **Admin** | Red "Admin" badge | Full access to all features and settings |
| **User** | Teal "User" badge | Access controlled by permissions assigned to the account |

Use the toolbar buttons to create a **New User** or **New Admin**. The screen header shows the current count of admins and users, and a **Refresh** button keeps the list in sync with the server.

You can search accounts by name or email using the search bar. Click any account row to open its detail panel where you can edit the name, email, password, permissions, and whether the account can operate on patients.

> Accounts that operates on patients can be used to as appointment operators. Accounts that do not (checkbox clear) will not show up when selecting the operator.

> **Permissions:** User accounts have granular permission levels for patients, appointments, pre‑op notes, post‑op notes, photos, expenses, notes, and labworks.

---

### Patients

The **Patients** screen is your main patient directory. Each row shows a patient's name, treatment labels (visual indicators of dental work), phone, last visit date, payment status, and more.

#### Toolbar

| Button | Action |
|--------|--------|
| **New Patient** | Create a new patient record |
| **Import** | Paste CSV data to bulk-import patients and appointments |
| **Export (n)** | Export selected patients and their appointments as CSV |

Select patients by clicking their rows (multi‑select is supported). The export button appears once at least one patient is selected.

#### Filters and sorting

- **Treatment filter** — Filter patients by a specific dental treatment (e.g., extraction, filling, crown)
- **by Name** — Toggle to sort alphabetically (tap again to reverse direction)
- **Column toggles** — Sort by any visible column (phone, last visit, payments, etc.)

The search bar filters patients in real time as you type. Use the **Show More** button at the bottom to load additional results.

#### Patient detail panel

Clicking a patient opens a multi‑tab panel:

##### Tab 1 — Patient Details

| Field | Description |
|-------|-------------|
| **Name** | Patient's full name |
| **Birth year** | Year of birth (used to calculate age) |
| **Gender** | Male ♂️ or Female ♀️ (dropdown) |
| **Email** | Email address with a quick‑action contact button |
| **Phone** | Phone numbers, the app automatically detects and validates numbers in international format. Detected numbers appear as clickable contact buttons. Invalid numbers show a warning. |
| **Address** | Physical address |
| **Notes** | Free‑text medical notes |
| **Tags** | Custom tags for filtering and categorization (type and press Enter to add) |

##### Tab 2 — Dental Notes

A visual teeth chart where you can record dental history for each tooth (ISO 3950 notation). This is for the patient's **permanent dental record**, not treatment‑specific notes.

- Tap a tooth to add or edit its note
- The chart shows both current notes and historical notes from past appointments
- For patients under 14, primary teeth are shown
- An **AI transcription** button at the bottom lets you dictate dental history from an audio recording

##### Tab 3 — Appointments

Lists all appointments for this patient, each shown as a card with pre‑op notes, post‑op notes, dental work, prescriptions, photos, and payment status. A **payment summary** at the bottom shows total cost, total paid, and whether the patient is fully paid, underpaid, or overpaid.

##### Tab 4 — Patient Page

Generate a secure web link that the patient can use to view their own appointments, payments, and photos. Click **Generate QR Link** to create the link, then share it or print a QR code for the patient.

### Importing & exporting patients

You can bulk‑import and export patient and appointment data using CSV. This is useful for migrating from another system or creating backups.

#### Importing

1. From the **Patients** screen, click the import button (copy icon labeled "Import") in the top toolbar.

2. A dialog will appear with two text fields:
   - **Patients**: Paste CSV data for patient records.
   - **Appointments**: Paste CSV data for appointment records.

3. The CSV data must have a header row with field names matching the application's field names. The **order of columns does not matter** — the application matches data by header names. The easiest way to get the correct format is to **export a sample first** and use that as a template.

   ##### Patient CSV fields

   | Field | Format | Description |
   |-------|--------|-------------|
   | `id` | text (UUID) | Unique identifier. If omitted, one is auto-generated. |
   | `title` | text | Patient's full name. |
   | `birth` | integer | Birth year (e.g., `1985`). Defaults to current year minus 18. |
   | `gender` | `0` or `1` | `0` = female, `1` = male. |
   | `phone` | text | Phone numbers in E.164 format, space-separated (e.g., `+1234567890 +9876543210`). |
   | `email` | text | Email address. |
   | `address` | text | Physical address. |
   | `notes` | text | Free-text medical notes. |
   | `tags/0`, `tags/1`, … | text | Patient tags. Each tag gets its own column (e.g., `tags/0` for the first tag, `tags/1` for the second). |
   | `teeth/11`, `teeth/12`, … | text | Dental chart notes per tooth. The number after `/` is the ISO 3950 tooth code (e.g., `teeth/11` for upper right central incisor). |
   | `archived` | `true` / `false` | Whether the patient is archived. |

   ##### Appointment CSV fields

   | Field | Format | Description |
   |-------|--------|-------------|
   | `id` | text (UUID) | Unique identifier. If omitted, one is auto-generated. |
   | `patientID` | text (UUID) | **Required.** The `id` of the patient this appointment belongs to. Must match an existing or imported patient. |
   | `date` | integer | **Minutes since Unix epoch** (not milliseconds). Example: `27213120` for Jan 1, 2022. |
   | `price` | decimal | Total price of the appointment (e.g., `150.00`). |
   | `paid` | decimal | Amount already paid (e.g., `50.00`). |
   | `preOpNotes` | text | Pre-operative notes. |
   | `postOpNotes` | text | Post-operative notes. |
   | `isDone` | `true` / `false` | Whether the appointment is completed. |
   | `operatorsIDs/0`, `operatorsIDs/1`, … | text (UUID) | IDs of the doctors/operators assigned. |
   | `prescriptions/0`, `prescriptions/1`, … | text | Prescriptions. |
   | `teeth/11`, `teeth/12`, … | text | Dental chart per tooth (ISO 3950 codes). |
   | `imgs/0`, `imgs/1`, … | text (URL) | Image URLs for the appointment. |
   | `hasLabwork` | `true` / `false` | Whether a lab case is associated. |
   | `labName` | text | Name of the lab. |
   | `labworkNotes` | text | Notes about the lab work. |
   | `labworkReceived` | `true` / `false` | Whether the lab work was received. |
   | `archived` | `true` / `false` | Whether the appointment is archived. |

   > **Important note about the date field**: Appointment dates are stored as integer minutes since January 1, 1970 (Unix epoch). To convert a date, use an online converter or calculate: `(date in milliseconds) / 60000`. For example, `2025-01-01 00:00 UTC` = `28877760`.

4. You can fill one or both fields — they are independent. For example, you can import only patients, only appointments, or both at once.

5. Click **Import** to add the records to the application.

> **Tip**: The fastest way to build a valid import file is to first export an existing patient, then follow the same column layout.

##### Exporting data

1. On the **Patients** screen, select one or more patients by clicking on their rows. Selected rows will be highlighted.

2. Once at least one patient is selected, an export button (with a count) will appear in the top toolbar. Click it.

3. The export dialog shows two tabs:
   - **Patients**: CSV data for the selected patients.
   - **Appointments**: CSV data for all appointments belonging to the selected patients.

4. You can customize the export output using the checkboxes at the top:
   - **Title**: Include/exclude the CSV header row.
   - **All**: Export all available columns, or pick specific columns individually.
   - Individual column checkboxes: Select which columns to include in the export.

5. Click the copy button at the bottom-right of the CSV preview to copy the data to your clipboard. You can then paste it into a spreadsheet application (like Excel or Google Sheets) or a text file.

### Appointment

After creating a patient, you can create an appointment for them. The appointment is divided to three sections:
- Pre-op
    - Patient name
    - Doctor
    - Date
    - Time
    - Pre-operative notes (this is typically where your staff enter their notes regarding the appointment)
- Post-op
    - Dental notes on a dental chart
    - Post-operative notes
    - Prescriptions
    - Price & payment status
    - Labwork related to this appointment
- Photos
    - Photos of the appointment (before and after)

> You can also use the AI-based voice to note. Where what you say can be processed by AI and used to fill all the forms above.

### Labworks

The **Labworks** screen tracks all lab cases across the clinic in a table view.

Click any column header to sort by that column. Use the **Show Done** toggle to include or hide received and delivered lab cases. The search bar filters by patient name, date, lab name, or notes.

> Labworks are tightly coupled with appointments. Each labwork record live inside an appointment data in your clinic.

---

### Notes

The **Notes** screen uses a **Kanban board** layout for organizing clinic notes visually.

- Each **column** represents a category or workflow stage
- Each **card** is a note with a title and body text
- Drag cards between columns to reorganize them
- Click **Add Column** to create a new category

Notes can be assigned to account, when an account is assigned to a new a note, they will receive a notification.
Notes can also have attachments as files.
Notes can also be recurring each specific amount of days.

#### When to use notes?

- To-dos in clinic that are not patient or appointment-related
- You have scheduled maintence of clinic (e.g. change AC filters)
- You want to send a file or a message for an account

---

### Expenses

The **Expenses** screen helps you track clinic spending organized by supplier.

#### Supplier list

Each supplier appears as a folder. The list shows:

- Supplier name with a folder icon
- **Last order** — how many days ago the most recent order was placed
- **Due payment** — outstanding amount highlighted in orange
- Archived suppliers show an "Archived" badge

Use the **⋯** menu on any supplier to **Open**, **Rename**, or **Archive/Restore** it.

The screen header shows the **total due** across all suppliers, and the **View All Orders** button opens a combined view of all orders regardless of supplier.


You can use **Scan Receipt** to scan a receipt photo, the app extracts supplier name, items, prices, and dates automatically. Choose between camera capture or gallery upload.

#### Supplier detail panel

Clicking a supplier opens its order list, divided into two sections:

- **Unpaid orders** — Orders that still have an outstanding balance
- **Paid orders** — Fully settled orders

Each order can be marked as paid or unpaid, and receipt images can be attached to any order.

If you have an order, and uploaded a receipt image, yet you still haven't added items to the order, you can use "read from photo" to use the AI-based scanner and extract items from the receipt.

---

### Settings

The **Settings** screen contains all configurable options for the application. Each setting is displayed as an expandable card showing its icon, title, and an indicator of whether it applies to the whole clinic or only your device.

#### General settings

| Setting | Scope | Description |
|---------|-------|-------------|
| **Currency** | 🌐 Whole clinic | Currency code used for all prices and payments |
| **Country code** | 🌐 Whole clinic | ISO country code used for phone number validation |
| **Prescription footer** | 🌐 Whole clinic | Text appended to the bottom of every printed prescription |
| **Phone number** | 🌐 Whole clinic | Clinic phone number shown on prescriptions and the patient web page |
| **Language** | 📱 Your device only | Interface language — does not sync to other devices |
| **Starting day of week** | 🌐 Whole clinic | First day shown on the calendar (Monday, Sunday, etc.) |
| **Date format** | 📱 Your device only | Month/day/year or day/month/year — device‑specific |
| **Dental notation** | 📱 Your device only | Tooth numbering system: ISO, Palmer, or Universal |

#### AI & advanced

| Setting | Scope | Description |
|---------|-------|-------------|
| **AI services** | 🌐 Whole clinic | Enable or disable AI‑powered features (voice transcription, receipt scanning). A privacy notice confirms your data is not used for training. |
| **Audio transcription locale** | 📱 Your device only | Language for voice‑to‑text transcription. Choose "Same as app language" or pick from 30+ supported languages. |
| **Cache reset** | 📱 Your device only | Clears all local data and re‑syncs from the server. Useful for troubleshooting. A progress dialog guides you through the process. |

> Service‑specific settings (SMTP, Backups, S3, Authentication, Meta) are documented in the [Best practices](#best-practices) section above.