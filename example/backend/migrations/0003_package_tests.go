package migrations

import (
	_ "embed"
	"fmt"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"

	"pocketbase_drift_example_backend/config"
)

// 0003_package_tests.json is test/test_data/test-pb_schema.json from the
// package root (ultimate, todo, active_todo) without its `users` entry: the
// stock users collection already exists with the same id (_pb_users_auth_)
// and keeps the public list/view rules set in 0002 for the lab clients. Keep
// both files and test/test_data/collections.json.dart in sync.
//
//go:embed 0003_package_tests.json
var packageTestsSchema []byte

func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(config.UsersCollection)
		if err != nil {
			return fmt.Errorf("failed to find users collection: %w", err)
		}
		// The package test schema declares a `username` text field on users.
		// No unique index: every lab user would share the empty username.
		if users.Fields.GetByName("username") == nil {
			users.Fields.Add(&core.TextField{Id: "text4166911607", Name: "username"})
			if err := app.Save(users); err != nil {
				return fmt.Errorf("failed to add users.username: %w", err)
			}
		}
		if err := app.ImportCollectionsByMarshaledJSON(packageTestsSchema, false); err != nil {
			return fmt.Errorf("failed to import package test collections: %w", err)
		}
		return nil
	}, func(app core.App) error {
		for _, name := range []string{"active_todo", "ultimate", "todo"} {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(c); err != nil {
				return fmt.Errorf("failed to delete %s: %w", name, err)
			}
		}
		users, err := app.FindCollectionByNameOrId(config.UsersCollection)
		if err != nil {
			return nil
		}
		users.Fields.RemoveByName("username")
		return app.Save(users)
	})
}
