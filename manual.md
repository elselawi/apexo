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

### Doctors

Creating doctors is useful if the clinic has more than one doctor, this would be useful for doctors to see and filter their own patients, appointments, statistics. It would also be useful if you want to show data only to specific users of the application, as you'll see below.

### Patients

Create a record for each patient in the clinic. Each patient can have their basic information like name, phone number, address, medical history etc. You can also add specific tags to each patient to make it easier to filter them.

Each patient also have "Dental chart" where you can store notes specific to a tooth of this patient.

Each patient would also have a list of appointments, where you can see each appointment details, notes, payment status, photos, prescriptions and more.

Finally, for each patient, the application would generate a link that the patient can use to see their appointments and photos stores to on their appointments.

### Appointment

After creating a patient, you can create an appointment for them. You can set the date, time, payment, and notes. You can also add photos to the appointment.

### Statistics

After creating some patients and appointments, you can see some statistics about the clinic. You can see the number of patients, appointments, payments, and more.

### Manage labworks

This screen has been designed to track labworks, their date, and whether they are delivered or not, paid or not.

Each labwork can be tied to a specific patient, and specific doctor.

### Manage expenses and receipts

You can also track expenses and receipts. In the expenses screen add receipts that can hold information such as the date, amount, description, items, and more.

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

#### Backups/Restore

You can use this section to see the backups that have been made and restore them. You can also create a new backup, and upload a backup from your device.

#### Administrators

You can add administrators to the application. Administrators can access all the features of the application and can also add other administrators.

They also have unrestricted access to the whole application and its data.

#### Users

Other than administrators, you can also add users to the application. Users can only access the features that are available to them.

Typically doctors, secretaries, and receptionists would all be users.

#### Permission

You can set the permissions for each user. For example you can set that users can not see statistics (only admins would).

#### Locking doctor to users

After creating doctors and users, you can lock a doctor appointments to be seen only by a specific set of users. To do this, go to the "Doctors" page and click on the doctor you want to lock, then write the email addresses of the users that are allowed to see the appointments of this doctor.

If this field is empty, then all users would be able to see the appointments of this doctor.