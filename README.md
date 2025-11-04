# Apexo


Apexo is application intended for simple and easy management of dental clinics. Its free and open source. It supports patient management, appointment management, photo attachments, multiple doctors, multiple users, works offline, synchronizes through multiple devices, multi-lingual, secure, supports backups.

[Website](https://apexo.app) - [Demo](https://demo.apexo.app) - [Download](https://apexo.app/#getting-started) - [Documentation](https://docs.apexo.app)

> The following document is technical documentation for the Apexo project. If you are a user, or would like to use the application please visit the [Apexo website](https://apexo.app), or read through the [manual.md](https://github.com/elselawi/apexo/blob/master/manual.md).

## Contributing

All contribution are welcome, whether as a PR or issue. All I ask is to adhere to Github community standards.

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

- __Windows__: All features should/are tested and works.
- __Android__: All features should/are tested and works.
- __Web__: partial support, photo uploading isn't supported (todo).
- __iOS__: planned, not yet implemented.
- __MacOS__: planned, not yet implemented.

## Testing

- [How to run ___unit testing___](https://github.com/elselawi/apexo/blob/master/test/unit_test_readme.md).
- [How to run ___integration testing___](https://github.com/elselawi/apexo/blob/master/integration_test/readme.md).


## Building

To build the application the common flutter commands should be used:

```
flutter build windows
flutter build apk
flutter build web
```

... etc.

However, to streamline distribution I've wrote the file [scripts/build_and_dist.dart](https://github.com/elselawi/apexo/blob/master/scripts/build_and_dist.dart) so that it builds for the supported platforms, then move the builds to _"dist"_ directory where the landing page would fetch and display download links for all versions.

## Support

Currently I'm not accepting any financial support for the development of this project. I'm developing it on my free time and using it in my own clinic.

If you insist to help:

- You can report issues or bugs.
- Submit PR request to improve the project.
- Pray for peace and better future in the middle east.


#### Built with ❤️ in Mosul, Iraq.

## License
GNU General Public License v3.0.
