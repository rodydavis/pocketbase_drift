# example

To get started download the latest binary from [pocketbase](https://pocketbase.io/docs/) and start a local server.

Set the username and password to the following:

```dart
const username = 'test@admin.com';
const password = 'Password123';
```

Start the server and you should be able to open the following url:

```bash
http://127.0.0.1:8090
```

Create a new collection called `todo` and add a field `name` with the type `text`.

Run the example app and you should be able to login with the above credentials.
