final offlineCollections = [
  {
    "id": "_pb_users_auth_",
    "name": "users",
    "type": "auth",
    "system": false,
    "schema": [
      {
        "id": "users_name",
        "name": "name",
        "type": "text",
        "system": false,
        "required": false,
        "options": {"min": null, "max": null, "pattern": ""}
      },
      {
        "id": "users_avatar",
        "name": "avatar",
        "type": "file",
        "system": false,
        "required": false,
        "options": {
          "maxSelect": 1,
          "maxSize": 5242880,
          "mimeTypes": [
            "image/jpeg",
            "image/png",
            "image/svg+xml",
            "image/gif",
            "image/webp"
          ],
          "thumbs": null,
          "protected": false
        }
      }
    ],
    "indexes": [],
    "listRule": "id = @request.auth.id",
    "viewRule": "id = @request.auth.id",
    "createRule": "",
    "updateRule": "id = @request.auth.id",
    "deleteRule": "id = @request.auth.id",
    "options": {
      "allowEmailAuth": true,
      "allowOAuth2Auth": true,
      "allowUsernameAuth": true,
      "exceptEmailDomains": null,
      "manageRule": null,
      "minPasswordLength": 8,
      "onlyEmailDomains": null,
      "requireEmail": false
    }
  },
  {
    "id": "l1qxa33evkxxte0",
    "name": "todo",
    "type": "base",
    "system": false,
    "schema": [
      {
        "id": "kp8porhx",
        "name": "name",
        "type": "text",
        "system": false,
        "required": false,
        "options": {"min": null, "max": null, "pattern": ""}
      },
      {
        "id": "pyqkkhqy",
        "name": "description",
        "type": "editor",
        "system": false,
        "required": false,
        "options": {}
      }
    ],
    "indexes": [],
    "listRule": "",
    "viewRule": "",
    "createRule": "",
    "updateRule": "",
    "deleteRule": "",
    "options": {}
  },
  {
    "id": "p1fq7xv6lor6sx5",
    "name": "ultimate",
    "type": "base",
    "system": false,
    "schema": [
      {
        "id": "obxvqtqv",
        "name": "plain_text",
        "type": "text",
        "system": false,
        "required": false,
        "options": {"min": null, "max": null, "pattern": ""}
      },
      {
        "id": "ceb2vide",
        "name": "rich_editor",
        "type": "editor",
        "system": false,
        "required": false,
        "options": {}
      },
      {
        "id": "4h9rnjbu",
        "name": "number",
        "type": "number",
        "system": false,
        "required": false,
        "options": {"min": null, "max": null}
      },
      {
        "id": "qztnpr6f",
        "name": "bool",
        "type": "bool",
        "system": false,
        "required": false,
        "options": {}
      },
      {
        "id": "prn0rg2i",
        "name": "email",
        "type": "email",
        "system": false,
        "required": false,
        "options": {"exceptDomains": null, "onlyDomains": null}
      },
      {
        "id": "oenxfjwg",
        "name": "url",
        "type": "url",
        "system": false,
        "required": false,
        "options": {"exceptDomains": null, "onlyDomains": null}
      },
      {
        "id": "om28ydd6",
        "name": "datetime",
        "type": "date",
        "system": false,
        "required": false,
        "options": {"min": "", "max": ""}
      },
      {
        "id": "lp7adu2b",
        "name": "select_single",
        "type": "select",
        "system": false,
        "required": false,
        "options": {
          "maxSelect": 1,
          "values": ["a", "b", "c", "d", "e", "f", "g", "h"]
        }
      },
      {
        "id": "wsivt1ec",
        "name": "select_multi",
        "type": "select",
        "system": false,
        "required": false,
        "options": {
          "maxSelect": 8,
          "values": ["a", "b", "c", "d", "e", "f", "g", "h"]
        }
      },
      {
        "id": "kmlgxtau",
        "name": "file_single",
        "type": "file",
        "system": false,
        "required": false,
        "options": {
          "maxSelect": 1,
          "maxSize": 5242880,
          "mimeTypes": [],
          "thumbs": [],
          "protected": false
        }
      },
      {
        "id": "wdqrxiv0",
        "name": "file_multi",
        "type": "file",
        "system": false,
        "required": false,
        "options": {
          "maxSelect": 99,
          "maxSize": 5242880,
          "mimeTypes": [],
          "thumbs": [],
          "protected": false
        }
      },
      {
        "id": "bw3xzvrk",
        "name": "relation_single",
        "type": "relation",
        "system": false,
        "required": false,
        "options": {
          "collectionId": "l1qxa33evkxxte0",
          "cascadeDelete": false,
          "minSelect": null,
          "maxSelect": 1,
          "displayFields": []
        }
      },
      {
        "id": "f99cberz",
        "name": "relation_multi",
        "type": "relation",
        "system": false,
        "required": false,
        "options": {
          "collectionId": "l1qxa33evkxxte0",
          "cascadeDelete": false,
          "minSelect": null,
          "maxSelect": null,
          "displayFields": []
        }
      },
      {
        "id": "uss3qfeg",
        "name": "json",
        "type": "json",
        "system": false,
        "required": false,
        "options": {}
      }
    ],
    "indexes": [],
    "listRule": null,
    "viewRule": null,
    "createRule": null,
    "updateRule": null,
    "deleteRule": null,
    "options": {}
  },
  {
    "id": "tf8pr2nvoa3u56g",
    "name": "active_todo",
    "type": "view",
    "system": false,
    "schema": [
      {
        "id": "4tmqdgvo",
        "name": "name",
        "type": "text",
        "system": false,
        "required": false,
        "options": {"min": null, "max": null, "pattern": ""}
      }
    ],
    "indexes": [],
    "listRule": null,
    "viewRule": null,
    "createRule": null,
    "updateRule": null,
    "deleteRule": null,
    "options": {"query": "SELECT id, name FROM todo\nWHERE name != ''"}
  }
];
