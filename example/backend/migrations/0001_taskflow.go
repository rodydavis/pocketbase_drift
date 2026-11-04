package migrations

import (
	_ "embed"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// 0001_taskflow.json is a verbatim copy of the example app's
// assets/pb_schema.json (projects + tasks), so the TaskFlow example runs
// against this backend with a matching local schema.
//
//go:embed 0001_taskflow.json
var taskflowSchema []byte

func init() {
	m.Register(func(app core.App) error {
		return app.ImportCollectionsByMarshaledJSON(taskflowSchema, false)
	}, func(app core.App) error {
		return nil
	})
}
