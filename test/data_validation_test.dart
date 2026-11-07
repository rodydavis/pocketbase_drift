import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocketbase_drift/pocketbase_drift.dart';

void main() {
  group('Data Validation Logic', () {
    late DataBase db;

    setUpAll(() {
      // We only need a memory database instance to access the validateData method.
      // No actual data will be stored.
      db = DataBase(DatabaseConnection(NativeDatabase.memory()));
    });

    // Helper function to create a mock CollectionModel for testing purposes.
    CollectionModel createTestCollection(List<CollectionField> fields) {
      return CollectionModel(
        id: 'test_collection_id',
        name: 'test_collection',
        type: 'base',
        system: false,
        listRule: null,
        viewRule: null,
        createRule: null,
        updateRule: null,
        deleteRule: null,
        fields: fields,
      );
    }

    test('throws exception for missing required field', () {
      final collection = createTestCollection([
        CollectionField({
          'id': 'f1',
          'name': 'required_text',
          'type': 'text',
          'required': true,
          'system': false,
          'data': {},
        })
      ]);

      // Test with field completely missing
      expect(
        () => db.validateData(collection, {'other_field': 'value'}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('Field required_text is required'))),
      );

      // Test with field being null
      expect(
        () => db.validateData(collection, {'required_text': null}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('Field required_text is required'))),
      );

      // Test with field being an empty string
      expect(
        () => db.validateData(collection, {'required_text': ''}),
        throwsA(isA<Exception>().having((e) => e.toString(), 'message',
            contains('Field required_text is required'))),
      );
    });

    test('validates various field types correctly', () {
      final collection = createTestCollection([
        CollectionField({
          'id': 'f_num',
          'name': 'num_field',
          'type': 'number',
          'required': false,
          'system': false,
          'data': {}
        }),
        CollectionField({
          'id': 'f_bool',
          'name': 'bool_field',
          'type': 'bool',
          'required': false,
          'system': false,
          'data': {}
        }),
        CollectionField({
          'id': 'f_date',
          'name': 'date_field',
          'type': 'date',
          'required': false,
          'system': false,
          'data': {}
        }),
        CollectionField({
          'id': 'f_email',
          'name': 'email_field',
          'type': 'email',
          'required': false,
          'system': false,
          'data': {}
        }),
        CollectionField({
          'id': 'f_url',
          'name': 'url_field',
          'type': 'url',
          'required': false,
          'system': false,
          'data': {}
        }),
      ]);

      // --- Number ---
      expect(
          () => db.validateData(collection, {'num_field': 'not a number'}),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('must be a number'))));
      expect(db.validateData(collection, {'num_field': 123}), isTrue);
      expect(db.validateData(collection, {'num_field': 123.45}), isTrue);

      // --- Bool ---
      expect(
          () => db.validateData(collection, {'bool_field': 'not a bool'}),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('must be a boolean'))));
      expect(
          () => db.validateData(collection, {'bool_field': 1}),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('must be a boolean'))));
      expect(db.validateData(collection, {'bool_field': true}), isTrue);

      // --- Date ---
      expect(
          () => db.validateData(collection, {'date_field': 'not a date'}),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message',
              contains('must be a valid ISO 8601 date string'))));
      expect(
          db.validateData(
              collection, {'date_field': DateTime.now().toIso8601String()}),
          isTrue);
      // Non-required date can be an empty string
      expect(db.validateData(collection, {'date_field': ''}), isTrue);

      // --- Email ---
      expect(
          () => db.validateData(collection, {'email_field': 'not-an-email'}),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message',
              contains('must be a valid email'))));
      expect(db.validateData(collection, {'email_field': 'test@example.com'}),
          isTrue);

      // --- URL ---
      expect(
          () => db.validateData(collection, {'url_field': 'not a valid url'}),
          throwsA(isA<Exception>().having((e) => e.toString(), 'message',
              contains('must be a valid URL string'))));
      expect(db.validateData(collection, {'url_field': 'https://example.com'}),
          isTrue);
    });

    test('validates single and multi-select fields (relation/file/select)', () {
      final collection = createTestCollection([
        CollectionField({
          'id': 'f_single',
          'name': 'single_relation',
          'type': 'relation',
          'required': false,
          'system': false,
          'maxSelect': 1
        }),
        CollectionField({
          'id': 'f_multi',
          'name': 'multi_relation',
          'type': 'relation',
          'required': false,
          'system': false,
          'maxSelect': 5
        }),
      ]);

      // Single select/relation/file
      expect(
          () => db.validateData(collection, {
                'single_relation': ['id1', 'id2']
              }),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('must be a string'))));
      expect(db.validateData(collection, {'single_relation': 'id1'}), isTrue);

      // Multi select/relation/file
      expect(
          () => db.validateData(collection, {'multi_relation': 'id1'}),
          throwsA(isA<Exception>().having(
              (e) => e.toString(), 'message', contains('must be a list'))));
      expect(
          db.validateData(collection, {
            'multi_relation': ['id1', 'id2']
          }),
          isTrue);
    });

    test('returns true for valid data and correctly ignores optional fields',
        () {
      final collection = createTestCollection([
        CollectionField({
          'id': 'f1',
          'name': 'required_text',
          'type': 'text',
          'required': true,
          'system': false,
          'data': {}
        }),
        CollectionField({
          'id': 'f2',
          'name': 'optional_number',
          'type': 'number',
          'required': false,
          'system': false,
          'data': {}
        }),
      ]);

      // Valid data with only required field
      expect(
          db.validateData(collection, {'required_text': 'some text'}), isTrue);

      // Valid data with all fields populated correctly
      expect(
          db.validateData(collection,
              {'required_text': 'some text', 'optional_number': 123}),
          isTrue);

      // Valid data with optional field explicitly null
      expect(
          db.validateData(collection,
              {'required_text': 'some text', 'optional_number': null}),
          isTrue);

      // Valid data with optional field missing
      expect(
          db.validateData(collection, {'required_text': 'some text'}), isTrue);
    });
  });
}
