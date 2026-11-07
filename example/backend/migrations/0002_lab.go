package migrations

import (
	"fmt"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"

	"pocketbase_drift_example_backend/config"
)

func autodates() []core.Field {
	return []core.Field{
		&core.AutodateField{Name: "created", OnCreate: true},
		&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
	}
}

func public(c *core.Collection) {
	c.ListRule = types.Pointer("")
	c.ViewRule = types.Pointer("")
	c.CreateRule = types.Pointer("")
	c.UpdateRule = types.Pointer("")
	c.DeleteRule = types.Pointer("")
}

func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId(config.UsersCollection)
		if err != nil {
			return fmt.Errorf("failed to find users collection: %w", err)
		}
		// Public read so `expand=author` works for every lab client.
		users.ListRule = types.Pointer("")
		users.ViewRule = types.Pointer("")
		if err := app.Save(users); err != nil {
			return fmt.Errorf("failed to update users rules: %w", err)
		}

		posts := core.NewBaseCollection(config.PostsCollection, "pbc_lab_posts001")
		public(posts)
		posts.Fields.Add(
			&core.TextField{Name: "title", Required: true, Max: 80},
			&core.TextField{Name: "body"},
			&core.RelationField{Name: "author", CollectionId: users.Id, MaxSelect: 1},
			&core.FileField{Name: "images", MaxSelect: 6, MaxSize: 10 << 20,
				Thumbs: []string{"100x100", "400x0"}},
			&core.FileField{Name: "cover", MaxSelect: 1, MaxSize: 10 << 20,
				Thumbs: []string{"100x100"}},
			&core.NumberField{Name: "likes"},
			&core.SelectField{Name: "status", MaxSelect: 1, Values: []string{"draft", "published"}},
			&core.DateField{Name: "due"},
		)
		posts.Fields.Add(autodates()...)
		if err := app.Save(posts); err != nil {
			return fmt.Errorf("failed to create posts: %w", err)
		}

		notes := core.NewBaseCollection(config.NotesCollection, "pbc_lab_notes001")
		owner := "owner = @request.auth.id"
		notes.ListRule = types.Pointer(owner)
		notes.ViewRule = types.Pointer(owner)
		notes.CreateRule = types.Pointer("@request.auth.id != ''")
		notes.UpdateRule = types.Pointer(owner)
		notes.DeleteRule = types.Pointer(owner)
		notes.Fields.Add(
			&core.RelationField{Name: "owner", Required: true, CollectionId: users.Id, MaxSelect: 1},
			&core.TextField{Name: "text"},
		)
		notes.Fields.Add(autodates()...)
		if err := app.Save(notes); err != nil {
			return fmt.Errorf("failed to create notes: %w", err)
		}

		// All rules nil: only superusers may touch it (403 for clients).
		locked := core.NewBaseCollection(config.LockedCollection, "pbc_lab_locked01")
		locked.Fields.Add(&core.TextField{Name: "title"})
		locked.Fields.Add(autodates()...)
		if err := app.Save(locked); err != nil {
			return fmt.Errorf("failed to create locked: %w", err)
		}

		// No `updated` autodate: some real collections only track `created`.
		events := core.NewBaseCollection(config.EventsCollection, "pbc_lab_events01")
		public(events)
		events.Fields.Add(
			&core.TextField{Name: "title"},
			&core.AutodateField{Name: "created", OnCreate: true},
		)
		if err := app.Save(events); err != nil {
			return fmt.Errorf("failed to create events: %w", err)
		}

		big := core.NewBaseCollection(config.BigCollection, "pbc_lab_big00001")
		public(big)
		big.Fields.Add(
			&core.TextField{Name: "name"},
			&core.NumberField{Name: "n"},
			&core.TextField{Name: "grp"},
			&core.RelationField{Name: "post", CollectionId: posts.Id, MaxSelect: 1},
		)
		big.Fields.Add(autodates()...)
		if err := app.Save(big); err != nil {
			return fmt.Errorf("failed to create big: %w", err)
		}
		return nil
	}, func(app core.App) error {
		for _, name := range []string{config.BigCollection, config.EventsCollection,
			config.LockedCollection, config.NotesCollection, config.PostsCollection} {
			c, err := app.FindCollectionByNameOrId(name)
			if err != nil {
				continue
			}
			if err := app.Delete(c); err != nil {
				return fmt.Errorf("failed to delete %s: %w", name, err)
			}
		}
		return nil
	})
}
