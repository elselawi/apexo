# Apexo


Apexo is application intended for simple and easy management of dental clinics. Its free and open source. It supports patient management, appointment management, photo attachments, multiple doctors, multiple users, works offline, synchronizes through multiple devices, multi-lingual, secure, supports backups.

[Website](https://apexo.app) - [Demo](https://demo.apexo.app) - [Download](https://apexo.app/#getting-started) - [Documentation](https://docs.apexo.app)

> The following document is technical documentation for the Apexo project. If you are a user, or would like to use the application please visit the [Apexo website](https://apexo.app), or read through the [manual.md](https://github.com/elselawi/apexo/blob/master/manual.md).

## Contributing

All contribution are welcome, whether as a PR or issue. All I ask is to adhere to Github community standards.

### Members contributed
- [sealine 150, Greek localization](https://github.com/sealine150).
- [Sammy Habta, Spanish localization](https://github.com/dojosgithub)

## Technology stack

This project uses [Dart](https://github.com/dart-lang/sdk) and [Flutter](https://github.com/flutter/flutter) to be able to run on multiple platforms from a single codebase. The design language is [Microsoft FluentUI](https://developer.microsoft.com/en-us/fluentui#/), as implemented thankfully [by Bruno D'Luka](https://github.com/bdlukaa).

The backend of this application should be [Pocketbase](https://pocketbase.io/).

I'm saying _"should"_ because I leave it up to the users to host their own backend. However, a cleanly installed pocketbase with a super user credentials would be enough to run this application since the application creates all the required collections and values on first login.

Check the [manual.md](https://github.com/elselawi/apexo/blob/master/manual.md) for how to install PocketBase.

In previous versions of apexo, [in an old github account of mine that I lost access to, and abandoned since then](https://github.com/alexcorvi/apexo), the tech-stack was quite different, Typescript/React to create a single page PWA and CouchDB as backend. However, with usage I have found that the web platform, although great for other application, was limiting for this application. So in summer 2024 I started a whole re-write of apexo and published it to my new github account.

- ___Can you migrate from that application to this one?___
   - __No you can't__, I'm sorry. This is a new release, the versioning isn't even a continuation from the old one.
   - However, I plan to support this version so that it will always be backwards compatible.

## Available platforms

- __Windows__: All features should/are tested and works (available on [Microsoft Store](https://apps.microsoft.com/detail/9n2j1h8dz6mt)).
- __Android__: All features should/are tested and works (available on [Google Play](https://play.google.com/store/apps/details?id=app.apexo.mobile)).
- __Web__: All features should/are tested and works (available on [web.apexo.app](https://web.apexo.app)).
- __iOS__: All features should/are tested and works (available on [App Store](https://apps.apple.com/us/app/apexo-app/id6767690393)).
- __MacOS__: All features should/are tested and works (available to [Download](https://apexo.app/#download)).

## Testing

- [How to run ___unit testing___](https://github.com/elselawi/apexo/blob/master/test/unit_test_readme.md).
- [How to run ___integration testing___](https://github.com/elselawi/apexo/blob/master/integration_test/readme.md).


## Building & Distribution

- For the web:
   - Build with the command: `flutter build web --release`
   - deploy to wrangler: `wrangler pages deploy build/web --project-name=apexo-web`

- For android:
   - Run: `shorebird release --platforms android -- --build-number=X` (replace X with build number, check on shorebird: https://console.shorebird.dev/orgs/44512/apps/34dc240a-bfe8-40d0-937e-f069465f0165)
   - Upload: `build/app/outputs/bundle/release/app-release.aab` to play console.

- For MacOS
   - build with: `shorebird release --platforms macos -- --release`
   - then run: `cd macos && pod install`
   - then `open with xcode` this should open `Runner.xcworkspace` not `Runner.xcodeproj`
   - then go to product -> archive
   - after build finishes it will open a new window -> Distribute -> direct distribute (for notarization)
   - wait for the notification
   - export it (from the same window of "archives")
   - staple: `xcrun stapler staple apexo.app`
   - make sure it was successful: `spctl --assess --verbose apexo.app`
   - create a dmg: `create-dmg --volname "Apexo Installer" --window-pos 200 120 --window-size 800 400 --icon-size 100 --icon "Apexo.app" 200 190 --hide-extension "Apexo.app" --app-drop-link 600 185 "apexo-installer.dmg" "apexo.app"`
   - Notarize DMG: `xcrun notarytool submit apexo-installer.dmg --apple-id "ali.a.saleem@outlook.com" --team-id "8T5VB3M83P" --password "APP_SPECIFIC_PASSWORD" --wait` (replace app specific password with the app specific password from macos directory).
   - staple dmg: `xcrun stapler staple apexo-installer.dmg`
   - Upload it: `wrangler r2 object put apexo-releases/releases/0.10.6/Apexo-Installer.dmg --file=Apexo-Installer.dmg --remote`
   - Update the `metadata.json` and upload it: `wrangler r2 object put apexo-releases/metadata.json --file=metadata.json --remote`

- For windows: (On a windows machine)
   - build with `shorebird release --platforms windows`
   - build msix: `dart run msix:create --store`
   - upload to ms store through microsoft partner
   
- For iOS:
   - build with `flutter build ipa --release --export-method app-store`
   - upload with transporter (build/ios/ipa) and deliver
   - continue on appstoreconnect `https://appstoreconnect.apple.com/apps/6767690393/distribution/ios/version/inflight`


## Support

Currently I'm not accepting any financial support for the development of this project. I'm developing it on my free time and using it in my own clinic.

If you insist to help:

- You can report issues or bugs.
- Submit PR request to improve the project.
- Pray for peace and better future in the middle east.


#### Built with ❤️ in Mosul, Iraq.

## License
GNU General Public License v3.0.