# Files

This guide covers file handling, caching, and the PocketBaseImageProvider.

## Overview

pocketbase_drift automatically caches files for offline access:
- Files are stored as blobs in the local SQLite database
- Cached files are available when offline
- File caching works with create, update, and fetch operations
- Thumbs (`thumb: '100x100'`) are cached separately from the original file
- Concurrent requests for the same file and thumb share one download (`client.files` is one instance per client)
- Downloads time out after 30 seconds by default (`timeout`)
- The blob cache has a size limit (`maxFileCacheBytes`, default 128 MB; 32 MB on the web). Eviction deletes oversized blobs first, then the least recently used ones. Blobs of pending and local-only records are never deleted (see "File Cache Size")

## Uploading Files

### Create with File

```dart
import 'package:http/http.dart' as http;

// From bytes
Future<RecordModel> createPostWithImage(Uint8List imageBytes) async {
  final file = http.MultipartFile.fromBytes(
    'image', // Field name in PocketBase schema
    imageBytes,
    filename: 'photo.jpg',
  );

  return client.collection('posts').create(
    body: {'title': 'Post with Image'},
    files: [file],
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );
}
```

### From File Picker

```dart
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

Future<void> pickAndUpload() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.image);
  if (result == null) return;

  final file = result.files.first;
  final bytes = file.bytes!;

  final multipartFile = http.MultipartFile.fromBytes(
    'image',
    bytes,
    filename: file.name,
  );

  await client.collection('posts').create(
    body: {'title': 'Uploaded Image'},
    files: [multipartFile],
    requestPolicy: RequestPolicy.cacheAndNetwork,
  );
}
```

### Multiple Files

```dart
final files = [
  http.MultipartFile.fromBytes('images', bytes1, filename: 'image1.jpg'),
  http.MultipartFile.fromBytes('images', bytes2, filename: 'image2.jpg'),
];

await client.collection('gallery').create(
  body: {'title': 'Gallery'},
  files: files,
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

## Update with File

```dart
await client.collection('posts').update(
  postId,
  body: {'title': 'Updated Post'},
  files: [newImageFile],
  requestPolicy: RequestPolicy.cacheAndNetwork,
);
```

Files are sent to the server one time. Later edits of the record do not upload the file again.

`requestTimeout` does not apply to writes with file uploads.

## PocketBaseImageProvider

Display cached images with automatic offline support. The provider loads bytes through `client.files.getFileBytes`, so it uses the same blob cache and `RequestPolicy`.

- The constructor is `const`.
- Two providers with the same client, record, file, `thumb`, `scale` and decode size are equal. Flutter's `ImageCache` keeps one entry for them.
- A failed load is removed from the `ImageCache`. The next build tries the load again.
- The provider has no `color` parameter and no `getFilterColor` method. Use `Image.color` and `Image.colorBlendMode` to tint an image.

```dart
import 'package:pocketbase_drift/pocketbase_drift.dart';

Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('image')!,
  ),
  width: 200,
  height: 150,
  fit: BoxFit.cover,
)
```

### With Placeholder and Error Handling

```dart
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: post.id,
    recordCollectionName: post.collectionName,
    filename: post.get<String>('cover_image')!,
  ),
  width: double.infinity,
  height: 200,
  fit: BoxFit.cover,
  loadingBuilder: (context, child, loadingProgress) {
    if (loadingProgress == null) return child;
    return Center(
      child: CircularProgressIndicator(
        value: loadingProgress.expectedTotalBytes != null
          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
          : null,
      ),
    );
  },
  errorBuilder: (context, error, stackTrace) {
    return Container(
      color: Colors.grey[300],
      child: const Icon(Icons.broken_image),
    );
  },
)
```

### With Thumbnail

For performance, use the `thumb` parameter. The server sends a resized image. The thumb is cached separately from the original file.

```dart
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('image')!,
    thumb: '200x200', // Request thumbnail from server
  ),
)
```

### Decode Size

Set a decode size to limit memory:

```dart
Image(
  image: PocketBaseImageProvider(
    client: client,
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('image')!,
    thumb: '400x0',
    pixelWidth: 400, // Physical pixels
    timeout: const Duration(seconds: 10),
  ),
)
```

The provider selects the decode size in this order:
1. `pixelWidth` and/or `pixelHeight`: the smallest size that covers the box and keeps the aspect ratio. The image is never enlarged.
2. `size` (logical pixels) multiplied by the device pixel ratio.
3. No value: the full image size.

## Get File Bytes Directly

```dart
final bytes = await client.files.getFileBytes(
  recordId: postRecord.id,
  recordCollectionName: postRecord.collectionName,
  filename: postRecord.get<String>('document')!,
  requestPolicy: RequestPolicy.cacheAndNetwork,
  // Optional:
  // thumb: '100x100',                   // Server-side thumb, cached separately
  // timeout: const Duration(seconds: 30), // Default
  // expireAfter: const Duration(days: 7), // Freshness: an expired copy is downloaded again online; still used offline until maintenance deletes it
);

// Use bytes (e.g., save to file, display PDF, etc.)
```

Behaviour:
- A cached copy that is not expired is returned without a network request.
- `RequestPolicy.cacheOnly` never downloads. It also returns an expired cached copy. Without a cached copy it throws `CacheMissException`.
- All other policies download when there is no cached copy or the copy is expired.
- If the download fails (also on timeout), an expired cached copy is returned. If no cached copy exists, the error is thrown.
- When the server is unreachable (no connection, socket error, or no answer within `timeout`), the download throws `ClientException` with status 0. `originalError` holds the cause (for example the `TimeoutException`).
- A server answer other than 200 throws the server's `ClientException` with the status code, URL and response.

```dart
try {
  final bytes = await client.files.getFileBytes(
    recordId: record.id,
    recordCollectionName: record.collectionName,
    filename: record.get<String>('document')!,
  );
} on ClientException catch (e) {
  if (e.statusCode == 0) {
    // Server unreachable or timeout, and no cached copy.
  } else {
    // Server answer, e.g. 404 (file not found) or 403 (no access).
    print('Download failed: ${e.statusCode}');
  }
}
```

## Get File URL

For direct URL access (network only):

```dart
final url = client.files.getUrl(
  record,
  record.get<String>('image')!,
);
// Returns: https://your-pb.com/api/files/collection/recordId/filename.jpg
```

## Reusable Image Widget

Create a wrapper for consistent usage:

```dart
class PbImage extends StatelessWidget {
  const PbImage({
    super.key,
    required this.record,
    required this.field,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.thumb,
  });

  final RecordModel record;
  final String field;
  final double? width;
  final double? height;
  final BoxFit fit;
  final String? thumb;

  @override
  Widget build(BuildContext context) {
    final filename = record.get<String>(field);
    if (filename == null || filename.isEmpty) {
      return _placeholder();
    }

    final client = ProviderScope.containerOf(context).read(pocketbaseProvider);

    return Image(
      image: PocketBaseImageProvider(
        client: client,
        recordId: record.id,
        recordCollectionName: record.collectionName,
        filename: filename,
        thumb: thumb,
      ),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey[200],
      child: const Icon(Icons.image_not_supported),
    );
  }
}

// Usage
PbImage(
  record: post,
  field: 'cover_image',
  width: double.infinity,
  height: 200,
  thumb: '400x0', // Width 400, auto height
)
```

## Offline File Behavior

### Create with Files (Offline)

When creating a record with files while offline:
1. Files are cached locally as blobs
2. Record is created with `synced: false, isNew: true`
3. When the server is reachable, sync sends the record with the files as multipart parts, one time
4. Server may rename files (adds unique suffix)
5. Cache updates the blobs to the server filenames

### Cached File Retrieval

```dart
// Returns the cached copy without a network request if it is not expired;
// downloads it otherwise. Works offline if the file was fetched before.
final bytes = await client.files.getFileBytes(
  recordId: recordId,
  recordCollectionName: 'posts',
  filename: 'image.jpg',
  requestPolicy: RequestPolicy.cacheFirst, // Try cache first
);
```

## Multi-File Fields

For fields that allow multiple files:

```dart
// Get list of filenames
final images = record.get<List<String>>('images') ?? [];

// Display all images
for (final filename in images) {
  Image(
    image: PocketBaseImageProvider(
      client: client,
      recordId: record.id,
      recordCollectionName: record.collectionName,
      filename: filename,
    ),
  );
}
```

## File Deletion

Removing files during update:

```dart
// Remove specific file (PocketBase syntax)
await client.collection('posts').update(
  postId,
  body: {
    'images-': ['old_image.jpg'], // Remove this file
  },
);

// Replace file
await client.collection('posts').update(
  postId,
  files: [newImageFile], // Replaces if single-file field
);
```

## File Cache Size

`maxFileCacheBytes` limits the blob cache: downloaded files, thumbs and the cached copies of uploads. The default is `$PocketBase.defaultMaxFileCacheBytes`: 128 MB, 32 MB on the web (the IndexedDB storage fallback keeps the whole database in memory). `null` disables the limit.

```dart
final client = $PocketBase.database(
  'https://example.pocketbase.io',
  maxFileCacheBytes: 64 * 1024 * 1024, // 64 MB; null = no limit
);
```

- After each blob write (download or cached upload copy), eviction runs in the background, one run at a time. It deletes blobs until the cache holds at most 90% of the limit (the eviction target): first the blobs larger than the target, then the least recently used ones.
- A cache hit marks a blob as used, at most once per hour per blob. A file that the server renamed after a push counts as used now. Blobs cached before the upgrade to 0.7.0 have no last-use time and are evicted first.
- Blobs of pending and local-only (`noSync`) records are never deleted: they are the only copy. This includes the pending uploads of another account. Blobs of a record deleted with `cacheOnly` can be deleted. When the pinned blobs alone keep the cache above the limit, eviction pauses until the cache grows by 10% of the limit or a sync pass ends.
- A file larger than 90% of the limit is returned but not cached: downloads, and the copies of uploads that the server accepted. Unsynced uploads are always stored. `client.fitsFileCache(bytes)` tells if a file of that size goes into the cache.
- `expireAfter` sets freshness, not the cache size. An expired copy is downloaded again when the server is reachable and is still used offline, until `runMaintenance()` with a TTL deletes it.

```dart
// Apply the limit now (the package does this after each blob write)
await client.enforceFileCacheLimit();

// Current cache size in bytes (pinned blobs included)
final bytes = await client.db.fileCacheBytes();

// Would a 20 MB file be cached?
final cached = client.fitsFileCache(20 * 1024 * 1024);
```

`client.db.setFile(recordId, filename, bytes)` returns `Future<void>`. Read a blob with `client.db.getFile(recordId, filename).getSingleOrNull()`. Write blobs only through `setFile`: it also writes the size and last use of the blob (table `BlobFileStats`). A blob inserted into `BlobFiles` with raw SQL has no stats row: the limit does not count it and never evicts it.

## File Cache Cleanup

Maintenance deletes blobs past their expiration and blobs of records that are no longer cached (only with a TTL), then applies `maxFileCacheBytes` (also with a `null` TTL):

```dart
final result = await client.runMaintenance();
print('Cleaned ${result.deletedFiles} expired or orphaned file blobs');
print('Evicted ${result.evictedFiles} blobs (${result.evictedBytes} bytes) for the size limit');
```
