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

From the left sidebar go to "settings" and the "mail settings". 

The following values are for gmail:
- Sender name: _your name_
- Sender email: _your email_
- SMTP host: __smtp.gmail.com__
- SMTP port: __587__
- SMTP username: _your email_
- SMTP password: _password_

The password field is the same password you use to login to your email account. However if you use 2-step verification you must generate an app password for this field [from your google account settings](https://myaccount.google.com/apppasswords).


The following values are for outlook:
- Sender name: _your name_
- Sender email: _your email_
- SMTP host: __smtp-mail.outlook.com__
- SMTP port: __587__
- SMTP username: _your email_
- SMTP password: _password_

The password field is the same password you use to login to your email account. However if you use 2-step verification you must generate an app password for this field [from your outlook account settings](https://account.live.com/proofs/Manage/additional).


For other email providers, you can find the SMTP settings in their documentation.

#### Setting up backups

Setting up backups is useful for making sure you don't lose your data in case of a server crash or a hacker attack. You can set up a backup schedule to run every day, week, month, or year.

From the left sidebar go to "settings" and the "backups".

The following image shows how to setup a backup schedule every day, or every week, bi-weekly, or every month. You can also setup how many backups to keep.

![Backups](https://raw.githubusercontent.com/elselawi/apexo/master/docs/manual_imgs/backups.png)

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


Once you've registered with an S3 provider, you'll have to create a bucket and get the following information: endpoint, bucket name, region, access key, and secret key. You can find the documentation for each provider on how to create a bucket and get the information.

Once you have the information, go to the "settings" page and then "Files storage". enable S3 storage, enter the information and save.

## How to use

### Accounts

In apexo, each user can have its own account. Account can be for an operator (doctor, hygienist, etc.) or for a non-operator (accountant, administrator, secretary, etc.). An account can be either an admin (where it has access to all features) or a regular user (where it has access to specific features based on permissions).


### Patients

- Create a record for each patient in the clinic. Each patient can have their basic information like name, phone number, address, medical history etc. You can also add specific tags to each patient to make it easier to filter them.

- Each patient also have "Dental chart" where you can store notes specific to a tooth of this patient. This chart usually can be used to register dental history, **not** treatments that has been done in your clinic, for your clinic's treatments, you should use appointments.

- Each patient would also have a list of appointments, where you can see each appointment details, notes, payment status, photos, prescriptions and more.

- Finally, for each patient, the application would generate a link that the patient can use to see their appointments and photos stores to on their appointments.

#### Importing & exporting patients

You can import and export patient and appointment data using the CSV format. This is useful for migrating data from another system, creating backups, or sharing data between clinics.

##### Importing data

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

> **Tip**: Click the info button (ℹ️) in the dialog for additional guidance on the expected CSV format. The fastest way to build a valid import file is to first export an existing patient, then follow the same column layout.

##### Exporting data

1. On the **Patients** screen, select one or more patients by clicking on their rows. Selected rows will be highlighted.

2. Once at least one patient is selected, an export button (copy icon with a count) will appear in the top toolbar. Click it.

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
    - Pre-operative notes
- Post-op
    - Post-operative notes
    - Dental notes on a dental chart
    - Prescriptions
    - Price & payment status
    - Labwork related to this appointment
- Photos
    - Photos of the appointment (before and after)

### Labworks

Labworks are used to track labwork orders, their date, and whether they are delivered or not. They can only be registered from the appointment page by clicking on "Add labwork for this appointment" at the bottom of the "operative details" page.

### Statistics

After creating some patients and appointments, you can see some statistics about the clinic. You can see the number of patients, appointments, payments, and more.

### Manage labworks

This screen has been designed to track labworks, their date, and whether they are delivered or not, paid or not.

Each labwork can be tied to a specific patient, and specific doctor.

### Manage expenses and receipts

To begin resitering expenses and receipts, go to the "expenses" page and add "supplier" first. Then you can add expenses and receipts under this supplier. Each supplier will appear as a folder icon, and when you open it a new window would open that contains two categories:

- Unpaid orders
- Paid orders

Each order can be marked as paid or unpaid, and each receipt can be attached to an order as an image.


### Setting

You can set the following settings:

#### Currency

Set the currency code to be used in the application.

#### Prescription footer

This is a piece of text that will be added to the bottom of each prescription.

#### Phone number

The phone number would be displayed in the patients web page and in the prescriptions.

#### Language

The language would be used in the application for menus, buttons and other text.

This setting would only be saved on the device that you're using. It would not be synced with the server.

#### Starting day of week

Set the starting day of the week. This would affect the way the calendar is displayed in the "appointments" page.

#### Date format

Set the date format to be used in the application. It can be "day/month/year" or "month/day/year".

This setting would only be saved on the device that you're using. It would not be synced with the server.

#### Dental notation

Set the dental notation system to be used in the application. It can be "ISO", "Palmer", or "Universal".

#### Backups/Restore

You can use this section to see the backups that have been made and restore them. You can also create a new backup, and upload a backup from your device.